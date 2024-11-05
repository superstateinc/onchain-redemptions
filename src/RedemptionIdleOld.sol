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

/// @title RedemptionIdleOld
/// @author Jon Walch and Max Wolff (Superstate) https://github.com/superstateinc
/// @notice A contract that allows Superstate Token holders to redeem their token for USDC, without deploying the idle USDC into lending protocols.
contract RedemptionIdleOld is Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

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

    /// @notice The ```SetMaximumOracleDelay``` event is emitted when the max oracle delay is set
    /// @param oldMaxOracleDelay The old max oracle delay
    /// @param newMaxOracleDelay The new max oracle delay
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @dev Event emitted when SUPERSTATE_TOKEN is redeemed for USDC
    /// @param redeemer The address of the entity redeeming
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    /// @param usdcOutAmount The amount of USDC the redeemer gets back
    event Redeem(address indexed redeemer, uint256 superstateTokenInAmount, uint256 usdcOutAmount);

    /// @dev Event emitted when tokens are withdrawn
    /// @param token The address of the token being withdrawn
    /// @param withdrawer The address of the caller
    /// @param to The address receiving the tokens
    /// @param amount The amount of token the redeemer gets back
    event Withdraw(address indexed token, address indexed withdrawer, address indexed to, uint256 amount);

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when there isn't enough token balance in the contract
    error InsufficientBalance();

    /// @dev Thrown when Chainlink Oracle data is bad
    error BadChainlinkData();

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
        // SUPERSTATE_TOKEN starts at $10.000000, Chainlink oracle with 6 decimals would represent as 10_000_000.
        // This math will give us 7_000_000 or $7.000000.
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
    /// @dev Can only be called by the owner
    function pause() external {
        _checkOwner();
        _requireNotPaused();

        _pause();
    }

    /// @notice Invokes the {Pausable-_unpause} internal function
    /// @dev Can only be called by the owner
    function unpause() external {
        _checkOwner();
        _requirePaused();

        _unpause();
    }

    // Oracle integration inspired by: https://github.com/FraxFinance/frax-oracles/blob/bd56532a3c33da95faed904a5810313deab5f13c/src/abstracts/ChainlinkOracleWithMaxDelay.sol

    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        if (maximumOracleDelay == _newMaxOracleDelay) revert BadArgs();
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }

    /// @notice The ```setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
    /// @dev Requires msg.sender to be the owner address
    /// @param _newMaxOracleDelay The new max oracle delay
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _checkOwner();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).latestRoundData();

        // If data is stale or below first price, set bad data to true and return
        // 1_000_000_000 is $10.000000 in the oracle format, that was our starting NAV per Share price for SUPERSTATE_TOKEN
        // The oracle should never return a price much lower than this
        _isBadData =
            _answer < int256(MINIMUM_ACCEPTABLE_PRICE) || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
        _updatedAt = _chainlinkUpdatedAt;
        _price = uint256(_answer);
    }

    /// @notice The ```getChainlinkPrice``` function returns the chainlink price and the timestamp of the last update
    /// @return _isBadData True if the data is stale or negative
    /// @return _updatedAt The timestamp of the last update
    /// @return _price The price
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        return _getChainlinkPrice();
    }

    /// @notice The ```maxUstbRedemptionAmount``` function returns the maximum amount of SUPERSTATE_TOKEN that can be redeemed based on the amount of USDC in the contract
    /// @return _superstateTokenAmount The maximum amount of SUPERSTATE_TOKEN that can be redeemed
    function maxUstbRedemptionAmount() external view returns (uint256 _superstateTokenAmount) {
        (,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        // divide a USDC amount by the USD per SUPERSTATE_TOKEN Chainlink price then scale back up to a SUPERSTATE_TOKEN amount
        _superstateTokenAmount = (USDC.balanceOf(address(this)) * CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION)
            / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    /// @notice The ```redeem``` function allows users to redeem SUPERSTATE_TOKEN for USDC at the current oracle price
    /// @dev Will revert if oracle data is stale or there is not enough USDC in the contract
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    function redeem(uint256 superstateTokenInAmount) external {
        if (superstateTokenInAmount == 0) revert BadArgs();
        _requireNotPaused();

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        // converts from a SUPERSTATE_TOKEN amount to a USD amount, and then scales back up to a USDC amount
        uint256 usdcOutAmount = (superstateTokenInAmount * usdPerUstbChainlinkRaw * USDC_PRECISION)
            / (CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION);

        if (USDC.balanceOf(address(this)) < usdcOutAmount) revert InsufficientBalance();

        SUPERSTATE_TOKEN.safeTransferFrom({from: msg.sender, to: address(this), value: superstateTokenInAmount});
        USDC.safeTransfer({to: msg.sender, value: usdcOutAmount});
        ISuperstateToken(address(SUPERSTATE_TOKEN)).burn(superstateTokenInAmount);

        emit Redeem({
            redeemer: msg.sender,
            superstateTokenInAmount: superstateTokenInAmount,
            usdcOutAmount: usdcOutAmount
        });
    }

    /// @notice The ```withdraw``` function allows the owner to withdraw any type of ERC20
    /// @dev Requires msg.sender to be the owner address
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of `_token` to withdraw
    function withdraw(address _token, address to, uint256 amount) external {
        _checkOwner();
        if (amount == 0) revert BadArgs();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        if (balance < amount) revert InsufficientBalance();

        token.safeTransfer({to: to, value: amount});
        emit Withdraw({token: _token, withdrawer: msg.sender, to: to, amount: amount});
    }
}
