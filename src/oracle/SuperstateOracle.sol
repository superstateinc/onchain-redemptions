// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

// TODO: do we need/want a pause on the oracle?
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol

/// @title SuperstateOracle
/// @author Jon Walch (Superstate) https://github.com/superstateinc
/// @notice A contract that allows Superstate to price USTB by extrapolating previous prices forward in real time
contract SuperstateOracle is AggregatorV3Interface, Ownable2Step {
    // TODO: notice explaining fields
    struct NavsCheckpoint {
        uint64 timestamp;
        uint64 effective_at;
        uint128 navs;
    }

    /// @notice Decimals of SuperstateTokens
    uint8 public constant DECIMALS = 6;

    /// @notice Version number of SuperstateOracle
    uint8 public constant VERSION = 1;

    /// @notice Number of days in seconds to keep extrapolating from latest checkpoint
    uint256 public constant LATEST_CHECKPOINT_GOOD_THROUGH = 5 * 24 * 60 * 60; // 5 days in seconds

    /// @notice Lowest acceptable Net Asset Value per Share price
    uint256 public immutable MINIMUM_ACCEPTABLE_PRICE;

    /// @notice Offchain Net Asset Value per Share checkpoints
    NavsCheckpoint[] public checkpoints;

    // TODO: read only list token contract address?

    /// @notice The ```NewCheckpoint``` event is emitted when a new checkpoint is added
    /// @param timestamp The 5pm ET timestamp of when this price was calculated for offchain
    /// @param effective_at When this checkpoint starts being used for pricing
    /// @param navs The Net Asset Value per Share (NAV/S) price (i.e. 10123456 is 10.123456)
    event NewCheckpoint(uint64 timestamp, uint64 effective_at, uint128 navs);

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when there aren't at least 2 checkpoints where block.timestamp is after the effective_at timestamps for both
    error CantGeneratePrice();

    /// @dev Thrown when the latest checkpoint is too stale to use to price
    error StaleCheckpoint();

    constructor(address initialOwner) Ownable(initialOwner) {
        // SUPERSTATE_TOKEN starts at $10.000000. An Oracle with 6 decimals would represent as 10_000_000.
        // This math will give us 7_000_000 or $7.000000.
        MINIMUM_ACCEPTABLE_PRICE = 7 * (10 ** uint256(DECIMALS));
    }

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function description() external pure override returns (string memory) {
        return "Realtime USTB Net Asset Value per Share (NAV/S) Oracle";
    }

    function version() external pure override returns (uint256) {
        return VERSION;
    }

    function _addCheckpoint(uint64 timestamp, uint64 effective_at, uint128 navs, bool override_effective_at) internal {
        uint256 nowTimestamp = block.timestamp;

        // timestamp should refer to 5pm ET of a previous business day
        if (timestamp >= nowTimestamp) revert BadArgs();

        // effective_at must be now or in the future
        if (effective_at < nowTimestamp) revert BadArgs();

        if (navs < MINIMUM_ACCEPTABLE_PRICE) revert BadArgs();

        // Can only add new checkpoints going chronologically forward
        if (checkpoints.length > 0) {
            NavsCheckpoint memory latest = checkpoints[checkpoints.length - 1];

            if (latest.timestamp >= timestamp || latest.effective_at >= effective_at) {
                revert BadArgs();
            }
        }

        // Revert if there is already a checkpoint with an effective_at in the future, unless override
        // Only start the check after 2 checkpoints, since two are needed to get a price at all
        if (checkpoints.length > 1 && checkpoints[checkpoints.length - 1].effective_at > nowTimestamp) {
            if (!override_effective_at) {
                revert BadArgs();
            }
        }

        checkpoints.push(NavsCheckpoint({timestamp: timestamp, effective_at: effective_at, navs: navs}));

        emit NewCheckpoint({timestamp: timestamp, effective_at: effective_at, navs: navs});
    }

    // TODO: notice
    function addCheckpoint(uint64 timestamp, uint64 effective_at, uint128 navs, bool override_effective_at) external {
        _checkOwner();

        _addCheckpoint({
            timestamp: timestamp,
            effective_at: effective_at,
            navs: navs,
            override_effective_at: override_effective_at
        });
    }

    // TODO: notice
    function addCheckpoints(NavsCheckpoint[] calldata _checkpoints, bool override_effective_at) external {
        _checkOwner();

        for (uint256 i = 0; i < _checkpoints.length; ++i) {
            _addCheckpoint({
                timestamp: _checkpoints[i].timestamp,
                effective_at: _checkpoints[i].effective_at,
                navs: _checkpoints[i].navs,
                override_effective_at: override_effective_at
            });
        }
    }

    // TODO: notice
    // TODO: public?
    function calculate_realtime_navs(
        uint128 unix_timestamp_to_price,
        uint128 early_navs,
        uint128 early_timestamp,
        uint128 later_navs,
        uint128 later_timestamp
    ) internal pure returns (uint128 answer) {
        answer = later_navs
            + ((later_navs - early_navs) * (unix_timestamp_to_price - later_timestamp))
                / (later_timestamp - early_timestamp);
    }

    // TODO: notice
    // will give different prices for the same _roundId based on the block.timestamp
    // startedAt and updatedAt give the timestamp of the price
    // only gives latest price
    function getRoundData(uint80)
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (checkpoints.length < 2) revert CantGeneratePrice(); // need at least two rounds. i.e. 0 and 1

        uint256 latestIndex = checkpoints.length - 1;
        uint128 nowTimestamp = uint128(block.timestamp);

        // We will only have one checkpoint that isn't effective yet the vast majority of the time
        while (latestIndex != 0 && checkpoints[latestIndex].effective_at > nowTimestamp) {
            latestIndex -= 1;
        }

        if (latestIndex == 0) revert CantGeneratePrice(); // need at least two rounds i.e. 0 and 1
        NavsCheckpoint memory later = checkpoints[latestIndex];
        NavsCheckpoint memory earlier = checkpoints[latestIndex - 1];

        if (nowTimestamp > later.effective_at + LATEST_CHECKPOINT_GOOD_THROUGH) {
            revert StaleCheckpoint();
        }

        uint128 realtime_navs = calculate_realtime_navs({
            unix_timestamp_to_price: nowTimestamp,
            early_navs: earlier.navs,
            early_timestamp: earlier.timestamp,
            later_navs: later.navs,
            later_timestamp: later.timestamp
        });

        roundId = uint80(latestIndex);
        answer = int256(uint256(realtime_navs));
        startedAt = nowTimestamp;
        updatedAt = nowTimestamp;
        answeredInRound = uint80(latestIndex);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = getRoundData(0);
    }
}
