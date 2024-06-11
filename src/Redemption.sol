// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUSTB} from "./IUSTB.sol";
import {IComet} from "./IComet.sol";

/// @title Redemption
/// @author Jon Walch and Max Wolff (Superstate) https://github.com/superstateinc
/// @notice A contract that allows USTB holders to redeem their USTB for USDC
contract Redemption {
    using SafeERC20 for IERC20;

    /// @notice Decimals of USDC
    uint256 public constant USDC_DECIMALS = 6;

    /// @notice Precision of USDC
    uint256 public constant USDC_PRECISION = 10 ** USDC_DECIMALS;

    /// @notice Decimals of USTB
    uint256 public constant USTB_DECIMALS = 6;

    /// @notice Precision of USTB
    uint256 public constant USTB_PRECISION = 10 ** USTB_DECIMALS;

    /// @notice Chainlink aggregator
    address public immutable CHAINLINK_FEED_ADDRESS;

    /// @notice Decimals of USTB/USD chainlink feed
    uint8 public immutable CHAINLINK_FEED_DECIMALS;

    /// @notice Precision of USTB/USD chainlink feed
    uint256 public immutable CHAINLINK_FEED_PRECISION;

    /// @notice The USTB contract
    IERC20 public immutable USTB;

    /// @notice The USDC contract
    IERC20 public immutable USDC;

    /// @notice The CompoundV3 contract
    IComet public immutable COMPOUND;

    /// @notice Admin address with exclusive privileges for withdrawing tokens
    address public immutable ADMIN;

    /// @notice Value, in seconds, that determines if chainlink data is too old
    uint256 public maximumOracleDelay;

    /// @notice The ```SetMaximumOracleDelay``` event is emitted when the max oracle delay is set
    /// @param oldMaxOracleDelay The old max oracle delay
    /// @param newMaxOracleDelay The new max oracle delay
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @dev Event emitted when USTB is redeemed for USDC
    /// @param redeemer The address of the entity redeeming
    /// @param ustbInAmount The amount of USTB to redeem
    /// @param usdcOutAmount The amount of USDC the redeemer gets back
    event Redeem(address indexed redeemer, uint256 ustbInAmount, uint256 usdcOutAmount);

    /// @dev Event emitted when tokens are withdrawn
    /// @param token The address of the token being withdrawn
    /// @param withdrawer The address of the caller
    /// @param to The address receiving the tokens
    /// @param amount The amount of token the redeemer gets back
    event Withdraw(address indexed token, address indexed withdrawer, address indexed to, uint256 amount);

    /// @dev Event emitted when usdc is deposited into the contract via the deposit function
    /// @param token The address of the token being deposited
    /// @param depositor The address of the caller
    /// @param amount The amount of token deposited
    event Deposit(address indexed token, address indexed depositor, uint256 amount);

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev Thrown when there isn't enough token balance in the contract
    error InsufficientBalance();

    /// @dev Thrown when Chainlink Oracle data is bad
    error BadChainlinkData();

    constructor(
        address _admin,
        address _ustb,
        address _ustbChainlinkFeedAddress,
        address _usdc,
        uint256 _maximumOracleDelay,
        address _compound
    ) {
        CHAINLINK_FEED_ADDRESS = _ustbChainlinkFeedAddress;
        CHAINLINK_FEED_DECIMALS = AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).decimals();
        CHAINLINK_FEED_PRECISION = 10 ** uint256(CHAINLINK_FEED_DECIMALS);

        maximumOracleDelay = _maximumOracleDelay;

        ADMIN = _admin;
        USTB = IERC20(_ustb);
        USDC = IERC20(_usdc);
        COMPOUND = IComet(_compound);

        require(ERC20(_ustb).decimals() == USTB_DECIMALS);
        require(ERC20(_usdc).decimals() == USDC_DECIMALS);
    }

    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }

    function _requireAuthorized() internal view {
        if (msg.sender != ADMIN) revert Unauthorized();
    }

    // Oracle integration borrowed from: https://github.com/FraxFinance/frax-oracles/blob/bd56532a3c33da95faed904a5810313deab5f13c/src/abstracts/ChainlinkOracleWithMaxDelay.sol

    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        if (maximumOracleDelay == _newMaxOracleDelay) revert BadArgs();
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }

    /// @notice The ```setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
    /// @dev Requires msg.sender to be the admin address
    /// @param _newMaxOracleDelay The new max oracle delay
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _requireAuthorized();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).latestRoundData();

        // If data is stale or below first price, set bad data to true and return
        // 10_000_000 is $10.000000 in the oracle format, that was our starting NAV per Share price for USTB
        // The oracle should never return a price much lower than this
        _isBadData = _answer <= 7_000_000 || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
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

    /// @notice The ```maxUstbRedemptionAmount``` function returns the maximum amount of USTB that can be redeemed based on the amount of USDC in the contract
    /// @return _ustbAmount The maximum amount of USTB that can be redeemed
    function maxUstbRedemptionAmount() external view returns (uint256 _ustbAmount) {
        (,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        // divide a USDC amount by the USD per USTB Chainlink price then scale back up to a USTB amount
        // 1 cUSDC = 1 USDC
        _ustbAmount = (COMPOUND.balanceOf(address(this)) * CHAINLINK_FEED_PRECISION * USTB_PRECISION)
            / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    /// @notice The ```redeem``` function allows users to redeem USTB for USDC at the current oracle price
    /// @dev Will revert if oracle data is stale or there is not enough USDC in the contract
    /// @param ustbInAmount The amount of USTB to redeem
    function redeem(uint256 ustbInAmount) external {
        if (ustbInAmount == 0) revert BadArgs();

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        // converts from a USTB amount to a USD amount, and then scales back up to a USDC amount
        uint256 usdcOutAmount =
            (ustbInAmount * usdPerUstbChainlinkRaw * USDC_PRECISION) / (CHAINLINK_FEED_PRECISION * USTB_PRECISION);

        if (COMPOUND.balanceOf(address(this)) < usdcOutAmount) revert InsufficientBalance();

        USTB.safeTransferFrom({from: msg.sender, to: address(this), value: ustbInAmount});
        COMPOUND.withdraw({asset: address(USDC), amount: usdcOutAmount});
        USDC.safeTransfer({to: msg.sender, value: usdcOutAmount});
        IUSTB(address(USTB)).burn(ustbInAmount);

        emit Redeem({redeemer: msg.sender, ustbInAmount: ustbInAmount, usdcOutAmount: usdcOutAmount});
    }

    /// @notice The ```withdraw``` function allows the admin to withdraw any type of ERC20
    /// @dev Requires msg.sender to be the admin address
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of `_token` to withdraw
    function withdraw(address _token, address to, uint256 amount) external {
        _requireAuthorized();
        if (amount == 0) revert BadArgs();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        if (balance < amount) revert InsufficientBalance();

        if (_token == address(COMPOUND)) {
            COMPOUND.withdraw({asset: address(USDC), amount: amount});
            USDC.safeTransfer({to: to, value: amount});
        } else {
            token.safeTransfer({to: to, value: amount});
        }

        emit Withdraw({token: _token, withdrawer: msg.sender, to: to, amount: amount});
    }

    /// @notice The ```deposit``` function transfer USDC from the caller to this contract and then to Compound v3 to accrue interest
    /// @param usdcAmount amount of approved usdc to put into this contract / deposit in compound
    function deposit(uint256 usdcAmount) external {
        _requireAuthorized();
        if (usdcAmount == 0) revert BadArgs();

        USDC.safeTransferFrom({from: msg.sender, to: address(this), value: usdcAmount});

        USDC.approve({spender: address(COMPOUND), value: usdcAmount});
        COMPOUND.supply({asset: address(USDC), amount: usdcAmount});

        emit Deposit({token: address(USDC), depositor: msg.sender, amount: usdcAmount});
    }
}
