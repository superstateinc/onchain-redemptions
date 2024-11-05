// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Redemption} from "./Redemption.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISuperstateToken} from "./ISuperstateToken.sol";
import {IComet} from "./IComet.sol";

/// @title RedemptionYield
/// @notice Implementation of Redemption that deploys idle USDC into Compound v3
contract RedemptionYield is Redemption {
    using SafeERC20 for IERC20;

    /// @notice The CompoundV3 contract
    IComet public immutable COMPOUND;

    /// @dev Event emitted when usdc is deposited into the contract via the deposit function
    event Deposit(address indexed token, address indexed depositor, uint256 amount);

    constructor(
        address _owner,
        address _superstateToken,
        address _superstateTokenChainlinkFeedAddress,
        address _usdc,
        uint256 _maximumOracleDelay,
        address _compound
    ) Redemption(_owner, _superstateToken, _superstateTokenChainlinkFeedAddress, _usdc, _maximumOracleDelay) {
        COMPOUND = IComet(_compound);
    }

    function maxUstbRedemptionAmount() external view override returns (uint256 _superstateTokenAmount) {
        (,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        _superstateTokenAmount = (
            COMPOUND.balanceOf(address(this)) * CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION
        ) / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    function redeem(uint256 superstateTokenInAmount) external override {
        if (superstateTokenInAmount == 0) revert BadArgs();
        _requireNotPaused();

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        uint256 usdcOutAmount = (superstateTokenInAmount * usdPerUstbChainlinkRaw * USDC_PRECISION)
            / (CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION);

        if (COMPOUND.balanceOf(address(this)) < usdcOutAmount) revert InsufficientBalance();

        SUPERSTATE_TOKEN.safeTransferFrom({from: msg.sender, to: address(this), value: superstateTokenInAmount});
        COMPOUND.withdrawTo({to: msg.sender, asset: address(USDC), amount: usdcOutAmount});
        ISuperstateToken(address(SUPERSTATE_TOKEN)).burn(superstateTokenInAmount);

        emit Redeem({
            redeemer: msg.sender,
            superstateTokenInAmount: superstateTokenInAmount,
            usdcOutAmount: usdcOutAmount
        });
    }

    function withdraw(address _token, address to, uint256 amount) external override {
        _checkOwner();
        if (amount == 0) revert BadArgs();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        if (_token == address(COMPOUND)) {
            if (amount == type(uint256).max) {
                uint256 compoundBalance = COMPOUND.balanceOf(address(this));
                COMPOUND.withdrawTo({to: to, asset: address(USDC), amount: amount});
                emit Withdraw({token: address(USDC), withdrawer: msg.sender, to: to, amount: compoundBalance});
            } else {
                COMPOUND.withdrawTo({to: to, asset: address(USDC), amount: amount});
                emit Withdraw({token: address(USDC), withdrawer: msg.sender, to: to, amount: amount});
            }
        } else {
            if (balance < amount) revert InsufficientBalance();

            token.safeTransfer({to: to, value: amount});
            emit Withdraw({token: _token, withdrawer: msg.sender, to: to, amount: amount});
        }
    }

    /// @notice Deposits USDC from the caller to this contract and then to Compound v3 to accrue interest
    /// @param usdcAmount amount of approved usdc to put into this contract / deposit in compound
    function deposit(uint256 usdcAmount) external {
        _checkOwner();
        if (usdcAmount == 0) revert BadArgs();

        USDC.safeTransferFrom({from: msg.sender, to: address(this), value: usdcAmount});
        USDC.approve({spender: address(COMPOUND), value: usdcAmount});
        COMPOUND.supply({asset: address(USDC), amount: usdcAmount});

        emit Deposit({token: address(USDC), depositor: msg.sender, amount: usdcAmount});
    }
}