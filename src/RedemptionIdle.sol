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

    /**
     * @dev This empty reserved space is put in place to allow future versions to inherit from new contracts
     * without impacting the fields within `RedemptionIdle`.
     */
    uint256[500] private __inheritanceGap;

    constructor(address _superstateToken, address _superstateTokenChainlinkFeedAddress, address _usdc)
        Redemption(_superstateToken, _superstateTokenChainlinkFeedAddress, _usdc)
    {}

    /// @notice The ```maxUstbRedemptionAmount``` function returns the maximum amount of SUPERSTATE_TOKEN that can be redeemed based on the amount of USDC in the contract
    /// @return superstateTokenAmount The maximum amount of SUPERSTATE_TOKEN that can be redeemed
    /// @return usdPerUstbChainlinkRaw The price used to calculate the superstateTokenAmount
    function maxUstbRedemptionAmount()
        external
        view
        override
        returns (uint256 superstateTokenAmount, uint256 usdPerUstbChainlinkRaw)
    {
        uint256 usdcOutAmountWithFee =
            (USDC.balanceOf(address(this)) * FEE_DENOMINATOR) / (FEE_DENOMINATOR - redemptionFee);

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw_) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        usdPerUstbChainlinkRaw = usdPerUstbChainlinkRaw_;

        // Round down, unlike `calculateUstbIn`, that way user doesn't send in more USTB than can be redeemed
        superstateTokenAmount = (usdcOutAmountWithFee * CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION)
            / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    /// @notice The ```_redeem``` function allows users to redeem SUPERSTATE_TOKEN for USDC at the current oracle price
    /// @dev Will revert if oracle data is stale or there is not enough USDC in the contract
    /// @param to The receiver address for the redeemed USDC
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    function _redeem(address to, uint256 superstateTokenInAmount) internal override {
        _requireNotPaused();

        (uint256 usdcOutAmount, uint256 usdcOutAmountWithFee, ) = _calculateUsdcOut(superstateTokenInAmount);

        if (USDC.balanceOf(address(this)) < usdcOutAmount) revert InsufficientBalance();

        SUPERSTATE_TOKEN.safeTransferFrom({from: msg.sender, to: address(this), value: superstateTokenInAmount});
        USDC.safeTransfer({to: to, value: usdcOutAmount});
        ISuperstateToken(address(SUPERSTATE_TOKEN)).offchainRedeem(superstateTokenInAmount);

        emit RedeemV3({
            redeemer: msg.sender,
            to: to,
            superstateTokenInAmount: superstateTokenInAmount,
            usdcOutAmount: usdcOutAmount,
            usdcOutAmountWithFee: usdcOutAmountWithFee
        });
    }

    /// @notice The ```withdraw``` function allows the owner to withdraw any type of ERC20
    /// @dev Requires msg.sender to be the owner address
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of `_token` to withdraw
    function withdraw(address _token, address to, uint256 amount) public override {
        _checkOwner();
        if (amount == 0) revert BadArgs();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

        if (balance < amount) revert InsufficientBalance();

        token.safeTransfer({to: to, value: amount});
        emit Withdraw({token: _token, withdrawer: msg.sender, to: to, amount: amount});
    }
}
