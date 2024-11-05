// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISuperstateToken} from "./ISuperstateToken.sol";
import {IRedemption} from "./interfaces/IRedemption.sol";

/// @title Redemption
/// @author Jon Walch and Max Wolff (Superstate)
/// @notice Abstract contract that provides base functionality for Superstate Token redemption
abstract contract Redemption is Pausable, Ownable2Step, IRedemption {
    /// @notice Decimals of USDC
    uint256 public constant USDC_DECIMALS = 6;

    /// @notice Precision of USDC
    uint256 public constant USDC_PRECISION = 10 ** USDC_DECIMALS;

    /// @notice Decimals of SUPERSTATE_TOKEN
    uint256 public constant SUPERSTATE_TOKEN_DECIMALS = 6;

    /// @notice Precision of SUPERSTATE_TOKEN
    uint256 public constant SUPERSTATE_TOKEN_PRECISION = 10 ** SUPERSTATE_TOKEN_DECIMALS;

    /// @notice Chainlink aggregator
    address public immutable CHAINLINK_FEED_ADDRESS;

    /// @notice Decimals of SUPERSTATE_TOKEN/USD chainlink feed
    uint8 public immutable CHAINLINK_FEED_DECIMALS;

    /// @notice Precision of SUPERSTATE_TOKEN/USD chainlink feed
    uint256 public immutable CHAINLINK_FEED_PRECISION;

    /// @notice Lowest acceptable chainlink oracle price
    uint256 public immutable MINIMUM_ACCEPTABLE_PRICE;

    /// @notice The SUPERSTATE_TOKEN contract
    IERC20 public immutable SUPERSTATE_TOKEN;

    /// @notice The USDC contract
    IERC20 public immutable USDC;

    /// @notice Value, in seconds, that determines if chainlink data is too old
    uint256 public maximumOracleDelay;

    constructor(
        address _owner,
        address _superstateToken,
        address _superstateTokenChainlinkFeedAddress,
        address _usdc,
        uint256 _maximumOracleDelay
    ) Ownable(_owner) {
        CHAINLINK_FEED_ADDRESS = _superstateTokenChainlinkFeedAddress;
        CHAINLINK_FEED_DECIMALS = AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).decimals();
        CHAINLINK_FEED_PRECISION = 10 ** uint256(CHAINLINK_FEED_DECIMALS);
        MINIMUM_ACCEPTABLE_PRICE = 7 * (10 ** uint256(CHAINLINK_FEED_DECIMALS));

        maximumOracleDelay = _maximumOracleDelay;

        SUPERSTATE_TOKEN = IERC20(_superstateToken);
        USDC = IERC20(_usdc);

        require(ERC20(_superstateToken).decimals() == SUPERSTATE_TOKEN_DECIMALS);
        require(ERC20(_usdc).decimals() == USDC_DECIMALS);
    }

    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }

    /// @notice Invokes the {Pausable-_pause} internal function
    function pause() external {
        _checkOwner();
        _requireNotPaused();
        _pause();
    }

    /// @notice Invokes the {Pausable-_unpause} internal function
    function unpause() external {
        _checkOwner();
        _requirePaused();
        _unpause();
    }

    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        if (maximumOracleDelay == _newMaxOracleDelay) revert BadArgs();
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }

    /// @notice Sets the max oracle delay to determine if Chainlink data is stale
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _checkOwner();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).latestRoundData();

        _isBadData =
            _answer < int256(MINIMUM_ACCEPTABLE_PRICE) || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
        _updatedAt = _chainlinkUpdatedAt;
        _price = uint256(_answer);
    }

    /// @notice Returns the chainlink price and the timestamp of the last update
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        return _getChainlinkPrice();
    }

    /// @notice Abstract function that must be implemented by derived contracts
    /// @return _superstateTokenAmount The maximum amount of SUPERSTATE_TOKEN that can be redeemed
    function maxUstbRedemptionAmount() external view virtual returns (uint256 _superstateTokenAmount);

    /// @notice Abstract function that must be implemented by derived contracts
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    function redeem(uint256 superstateTokenInAmount) external virtual;

    /// @notice Abstract function that must be implemented by derived contracts
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of token to withdraw
    function withdraw(address _token, address to, uint256 amount) external virtual;
}
