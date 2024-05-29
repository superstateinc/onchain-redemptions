// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Redemption {
    using SafeERC20 for IERC20;

    /// @notice Chainlink aggregator
    address public immutable CHAINLINK_FEED_ADDRESS;

    /// @notice Decimals of ETH/USD chainlink feed
    uint8 public immutable CHAINLINK_FEED_DECIMALS;

    /// @notice Precision of ETH/USD chainlink feed
    uint256 public immutable CHAINLINK_FEED_PRECISION;

    uint256 public maximumOracleDelay;

    IERC20 public immutable USTB;

    IERC20 public immutable USDC;

    /// @notice Admin address with exclusive privileges for withdrawing tokens
    address public immutable ADMIN;

    /// @dev TODO
    error BadArgs();

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev TODO
    error InsufficientBalance();

    constructor(address _admin, address _ustb, address _ustbChainlinkFeedAddress, address _usdc) {
        CHAINLINK_FEED_ADDRESS = _ustbChainlinkFeedAddress;
        CHAINLINK_FEED_DECIMALS = AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).decimals();
        CHAINLINK_FEED_PRECISION = 10 ** uint256(CHAINLINK_FEED_DECIMALS);

        // TODO: currently 28 hours in seconds, confirm with chainlink their write cadence which should always be 24 hours
        maximumOracleDelay = 100_800; // TODO param

        ADMIN = _admin;
        USTB = IERC20(_ustb);
        USDC = IERC20(_usdc);
    }

    function _requireAuthorized() internal view {
        require(msg.sender == ADMIN, "Not admin"); // TODO
    }

    // Oracle integration borrowed from: https://github.com/FraxFinance/frax-oracles/blob/bd56532a3c33da95faed904a5810313deab5f13c/src/abstracts/ChainlinkOracleWithMaxDelay.sol

    /// @notice The ```SetMaximumOracleDelay``` event is emitted when the max oracle delay is set
    /// @param oldMaxOracleDelay The old max oracle delay
    /// @param newMaxOracleDelay The new max oracle delay
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @notice The ```_setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
    /// @param _newMaxOracleDelay The new max oracle delay
    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        require(maximumOracleDelay != _newMaxOracleDelay, "delays cant be the same"); //TODO
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }

    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _requireAuthorized();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).latestRoundData();

        // If data is stale or negative, set bad data to true and return
        _isBadData = _answer <= 0 || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
        _updatedAt = _chainlinkUpdatedAt;
        _price = uint256(_answer);
    }

    /// @notice The ```getChainlinkPrice``` function returns the chainlink price and the timestamp of the last update
    /// @dev Uses the same prevision as the chainlink feed, virtual so it can be overridden
    /// @return _isBadData True if the data is stale or negative
    /// @return _updatedAt The timestamp of the last update
    /// @return _price The price
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        return _getChainlinkPrice();
    }

    function redeem(uint256 ustbRedemptionAmount) external {
        require(ustbRedemptionAmount > 0, "ustbRedemptionAmount cannot be 0"); //TODO

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();

        require(!isBadData, "isbaddata"); //TODO

        // usdcOut will always be larger than ustbRedemptionAmount because ustb price only goes up and started at 10
        uint256 usdcOut = (ustbRedemptionAmount * usdPerUstbChainlinkRaw) / CHAINLINK_FEED_PRECISION;

        require(USDC.balanceOf(address(this)) >= usdcOut, "usdcOut > contract balance"); //TODO

        USTB.safeTransferFrom({from: msg.sender, to: address(this), value: ustbRedemptionAmount});
        USDC.safeTransfer({to: msg.sender, value: usdcOut});

        // TODO: generate and use USTB interface
        bytes memory data = abi.encodeWithSignature("burn(uint256)", ustbRedemptionAmount);
        (bool success,) = address(USTB).call(data);
        require(success, "TODO");

        //TODO: emit event
    }

    function withdraw(address _token, address to, uint256 amount) external {
        _requireAuthorized();
        //        require(amount > 0, BadArgs());
        require(amount > 0, "Amount cant be zero"); // TODO

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        //        require(balance >= amount, InsufficientBalance());
        require(balance >= amount, "Not enough balance"); //TODO

        token.safeTransfer({to: to, amount: amount});

        //TODO: emit event
    }
}
