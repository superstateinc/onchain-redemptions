// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Redemption} from "./Redemption.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISuperstateToken} from "./ISuperstateToken.sol";

/// @title RedemptionIdle
/// @notice Implementation of Redemption that keeps USDC idle in the contract
contract RedemptionIdle is Redemption {
    using SafeERC20 for IERC20;

    constructor(
        address _owner,
        address _superstateToken,
        address _superstateTokenChainlinkFeedAddress,
        address _usdc,
        uint256 _maximumOracleDelay
    ) Redemption(_owner, _superstateToken, _superstateTokenChainlinkFeedAddress, _usdc, _maximumOracleDelay) {}

    function maxUstbRedemptionAmount() external view override returns (uint256 _superstateTokenAmount) {
        (,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        _superstateTokenAmount = (USDC.balanceOf(address(this)) * CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION)
            / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    function redeem(uint256 superstateTokenInAmount) external override {
        if (superstateTokenInAmount == 0) revert BadArgs();
        _requireNotPaused();

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

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

    function withdraw(address _token, address to, uint256 amount) external override {
        _checkOwner();
        if (amount == 0) revert BadArgs();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        if (balance < amount) revert InsufficientBalance();

        token.safeTransfer({to: to, value: amount});
        emit Withdraw({token: _token, withdrawer: msg.sender, to: to, amount: amount});
    }
}