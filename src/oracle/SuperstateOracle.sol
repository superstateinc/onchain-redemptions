// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title SuperstateOracle
/// @author Jon Walch (Superstate) https://github.com/superstateinc
/// @notice A contract that allows Superstate to price USTB by extrapolating previous prices forward in real time
contract SuperstateOracle is AggregatorV3Interface, Ownable2Step {
    /// @notice Represents a checkpoint for a Net Asset Value per Share (NAV/S) for a specific Superstate Business Day
    struct NavsCheckpoint {
        /// @notice The timestamp of 5pm ET of the Superstate Business day for this NAV/S
        uint64 timestamp;
        /// @notice The timestamp from which this NAV/S price can be used for realtime pricing
        uint64 effectiveAt;
        /// @notice The NAV/S at this checkpoint
        uint128 navs;
    }

    /// @notice Number of days in seconds to keep extrapolating from latest checkpoint
    uint256 public constant CHECKPOINT_EXPIRATION_PERIOD = 5 * 24 * 60 * 60; // 5 days in seconds

    /// @notice The address of the USTB token proxy contract that this oracle prices
    address public immutable USTB_TOKEN_PROXY_ADDRESS;

    /// @notice Decimals of SuperstateTokens
    uint8 public constant DECIMALS = 6;

    /// @notice Version number of SuperstateOracle
    uint8 public constant VERSION = 1;

    /// @notice Highest accepted delta between new Net Asset Value per Share price and the last one
    uint256 public maximumAcceptablePriceDelta;

    /// @notice Offchain Net Asset Value per Share checkpoints
    NavsCheckpoint[] public checkpoints;

    /// @notice The ```NewCheckpoint``` event is emitted when a new checkpoint is added
    /// @param timestamp The 5pm ET timestamp of when this price was calculated for offchain
    /// @param effectiveAt When this checkpoint starts being used for pricing
    /// @param navs The Net Asset Value per Share (NAV/S) price (i.e. 10123456 is 10.123456)
    event NewCheckpoint(uint64 timestamp, uint64 effectiveAt, uint128 navs);

    /// @notice The ```UpdatedMaximumAcceptablePriceDelta``` event is emitted when a new checkpoint is added
    /// @param oldDelta The old delta value
    /// @param newDelta The new delta value
    event SetMaximumAcceptablePriceDelta(uint256 oldDelta, uint256 newDelta);

    /// @dev Thrown when an argument to a function is not acceptable
    error BadArgs();

    /// @dev Thrown when there aren't at least 2 checkpoints where block.timestamp is after the effectiveAt timestamps for both
    error CantGeneratePrice();

    /// @dev Thrown when the effectiveAt argument is invalid
    error EffectiveAtInvalid();

    /// @dev Thrown when the effectiveAt argument is not chronologically valid
    error EffectiveAtNotChronological();

    /// @dev Thrown when there is an effectiveAt in the future for a previously written checkpoint
    error ExistingPendingEffectiveAt();

    /// @dev Thrown when the navs argument is too low
    error NetAssetValuePerShareTooLow();

    /// @dev Thrown when the navs argument is too high
    error NetAssetValuePerShareTooHigh();

    /// @dev Thrown when the function is not implemented
    error NotImplemented();

    /// @dev Thrown when the latest checkpoint is too stale to use to price
    error StaleCheckpoint();

    /// @dev Thrown when the timestamp argument is invalid
    error TimestampInvalid();

    /// @dev Thrown when the timestamp argument is chronologically invalid
    error TimestampNotChronological();

    constructor(address initialOwner, address ustbTokenProxy, uint256 _maximumAcceptablePriceDelta)
        Ownable(initialOwner)
    {
        USTB_TOKEN_PROXY_ADDRESS = ustbTokenProxy;
        _setMaximumAcceptablePriceDelta(_maximumAcceptablePriceDelta);
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

    function _setMaximumAcceptablePriceDelta(uint256 _newMaximumAcceptablePriceDelta) internal {
        if (maximumAcceptablePriceDelta == _newMaximumAcceptablePriceDelta) revert BadArgs();
        emit SetMaximumAcceptablePriceDelta({
            oldDelta: maximumAcceptablePriceDelta,
            newDelta: _newMaximumAcceptablePriceDelta
        });
        maximumAcceptablePriceDelta = _newMaximumAcceptablePriceDelta;
    }
    /**
     * @notice The ```setMaximumAcceptablePriceDelta``` function sets the max acceptable price delta between the last NAV/S price and the new one being added
     * @dev Requires msg.sender to be the owner address
     * @param _newMaximumAcceptablePriceDelta The new max acceptable price delta
     */

    function setMaximumAcceptablePriceDelta(uint256 _newMaximumAcceptablePriceDelta) external {
        _checkOwner();
        _setMaximumAcceptablePriceDelta(_newMaximumAcceptablePriceDelta);
    }

    /// @notice Adds a new NAV/S checkpoint
    /// @dev This function performs various checks to ensure the validity of the new checkpoint
    /// @param timestamp The timestamp of the checkpoint (should be 5pm ET of the business day)
    /// @param effectiveAt The time from which this checkpoint becomes effective (must be now or in the future)
    /// @param navs The Net Asset Value per Share for this checkpoint
    /// @param shouldOverrideEffectiveAt Flag to allow overriding an existing pending effective timestamp
    function _addCheckpoint(uint64 timestamp, uint64 effectiveAt, uint128 navs, bool shouldOverrideEffectiveAt)
        internal
    {
        uint256 nowTimestamp = block.timestamp;

        // timestamp should refer to 5pm ET of a previous business day
        if (timestamp >= nowTimestamp) revert TimestampInvalid();

        // effectiveAt must be now or in the future
        if (effectiveAt < nowTimestamp) revert EffectiveAtInvalid();

        // Can only add new checkpoints going chronologically forward
        if (checkpoints.length > 0) {
            NavsCheckpoint memory latest = checkpoints[checkpoints.length - 1];
            if (navs > latest.navs + maximumAcceptablePriceDelta) revert NetAssetValuePerShareTooHigh();
            if (navs < latest.navs - maximumAcceptablePriceDelta) revert NetAssetValuePerShareTooLow();

            if (latest.timestamp >= timestamp) {
                revert TimestampNotChronological();
            }

            if (latest.effectiveAt >= effectiveAt) {
                revert EffectiveAtNotChronological();
            }
        }

        // Revert if there is already a checkpoint with an effectiveAt in the future, unless override
        // Only start the check after 2 checkpoints, since two are needed to get a price at all
        if (checkpoints.length > 1 && checkpoints[checkpoints.length - 1].effectiveAt > nowTimestamp) {
            if (!shouldOverrideEffectiveAt) {
                revert ExistingPendingEffectiveAt();
            }
        }

        checkpoints.push(NavsCheckpoint({timestamp: timestamp, effectiveAt: effectiveAt, navs: navs}));

        emit NewCheckpoint({timestamp: timestamp, effectiveAt: effectiveAt, navs: navs});
    }

    /// @notice Adds a single NAV/S checkpoint
    /// @dev This function can only be called by the contract owner. Automated systems should only use this and not `addCheckpoints`
    /// @param timestamp The timestamp of the checkpoint
    /// @param effectiveAt The time from which this checkpoint becomes effective
    /// @param navs The Net Asset Value per Share for this checkpoint
    /// @param shouldOverrideEffectiveAt Flag to allow overriding an existing pending effective timestamp
    function addCheckpoint(uint64 timestamp, uint64 effectiveAt, uint128 navs, bool shouldOverrideEffectiveAt)
        external
    {
        _checkOwner();

        _addCheckpoint({
            timestamp: timestamp,
            effectiveAt: effectiveAt,
            navs: navs,
            shouldOverrideEffectiveAt: shouldOverrideEffectiveAt
        });
    }

    /// @notice Adds multiple NAV/S checkpoints at once
    /// @dev This function can only be called by the contract owner. Should not be used via automated systems.
    /// @param _checkpoints An array of NavsCheckpoint structs to be added
    function addCheckpoints(NavsCheckpoint[] calldata _checkpoints) external {
        _checkOwner();

        for (uint256 i = 0; i < _checkpoints.length; ++i) {
            _addCheckpoint({
                timestamp: _checkpoints[i].timestamp,
                effectiveAt: _checkpoints[i].effectiveAt,
                navs: _checkpoints[i].navs,
                shouldOverrideEffectiveAt: true
            });
        }
    }

    /// @notice Calculates the real-time NAV based on two checkpoints
    /// @dev Uses linear interpolation to estimate the NAV/S at the target timestamp
    /// @param targetTimestamp The timestamp for which to calculate the NAV/S
    /// @param earlierCheckpointNavs The NAV/S of the earlier checkpoint
    /// @param earlierCheckpointTimestamp The timestamp of the earlier checkpoint
    /// @param laterCheckpointNavs The NAV/S of the later checkpoint
    /// @param laterCheckpointTimestamp The timestamp of the later checkpoint
    /// @return answer The calculated real-time NAV/S
    function calculateRealtimeNavs(
        uint128 targetTimestamp,
        uint128 earlierCheckpointNavs,
        uint128 earlierCheckpointTimestamp,
        uint128 laterCheckpointNavs,
        uint128 laterCheckpointTimestamp
    ) public pure returns (uint128 answer) {
        uint128 timeSinceLastNav = targetTimestamp - laterCheckpointTimestamp;
        uint128 timeBetweenNavs = laterCheckpointTimestamp - earlierCheckpointTimestamp;

        uint128 navDelta;
        if (laterCheckpointNavs >= earlierCheckpointNavs) {
            navDelta = laterCheckpointNavs - earlierCheckpointNavs;
        } else {
            navDelta = earlierCheckpointNavs - laterCheckpointNavs;
        }

        uint128 extrapolatedChange = (navDelta * timeSinceLastNav) / timeBetweenNavs;

        if (laterCheckpointNavs >= earlierCheckpointNavs) {
            // Price is increasing or flat, this branch should almost always be taken
            answer = laterCheckpointNavs + extrapolatedChange;
        } else {
            // Price is decreasing, very rare, we might not ever see this happen
            answer = laterCheckpointNavs - extrapolatedChange;
        }
    }

    /// @notice Placeholder function to comply with the Chainlink AggregatorV3Interface
    /// @dev This function is not implemented and will always revert
    /// @dev param: roundId The round ID (unused)
    /// @return Tuple of round data (never actually returned)
    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert NotImplemented();
    }

    /// @notice Retrieves the latest NAV/S real-time price data
    /// @dev Calculates the current NAV/S based on the two most recent valid checkpoints
    /// @return roundId The ID of the latest round
    /// @return answer The current NAV/S
    /// @return startedAt The timestamp when this round started (current block timestamp)
    /// @return updatedAt The timestamp of the last update (current block timestamp, won't ever update)
    /// @return answeredInRound The round ID in which the answer was computed
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (checkpoints.length < 2) revert CantGeneratePrice(); // need at least two rounds. i.e. 0 and 1

        uint256 latestIndex = checkpoints.length - 1;
        uint128 nowTimestamp = uint128(block.timestamp);

        // We will only have one checkpoint that isn't effective yet the vast majority of the time
        while (checkpoints[latestIndex].effectiveAt > nowTimestamp) {
            latestIndex -= 1;
            if (latestIndex == 0) revert CantGeneratePrice(); // need at least two rounds i.e. 0 and 1
        }

        NavsCheckpoint memory laterCheckpoint = checkpoints[latestIndex];
        NavsCheckpoint memory earlierCheckpoint = checkpoints[latestIndex - 1];

        if (nowTimestamp > laterCheckpoint.effectiveAt + CHECKPOINT_EXPIRATION_PERIOD) {
            revert StaleCheckpoint();
        }

        uint128 realtimeNavs = calculateRealtimeNavs({
            targetTimestamp: nowTimestamp,
            earlierCheckpointNavs: earlierCheckpoint.navs,
            earlierCheckpointTimestamp: earlierCheckpoint.timestamp,
            laterCheckpointNavs: laterCheckpoint.navs,
            laterCheckpointTimestamp: laterCheckpoint.timestamp
        });

        roundId = uint80(latestIndex);
        answer = int256(uint256(realtimeNavs));
        startedAt = nowTimestamp;
        updatedAt = nowTimestamp;
        answeredInRound = uint80(latestIndex);
    }
}
