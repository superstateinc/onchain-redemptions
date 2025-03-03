// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Redemption} from "./Redemption.sol";
import {IRedemptionYield} from "src/interfaces/IRedemptionYield.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISuperstateToken} from "./ISuperstateToken.sol";
import {IComet} from "./IComet.sol";

/// @title RedemptionYield
/// @author Jon Walch and Max Wolff (Superstate) https://github.com/superstateinc
/// @notice Implementation of Redemption that deploys idle USDC into Compound v3
contract RedemptionYield is Redemption {
    using SafeERC20 for IERC20;

    /**
     * @dev This empty reserved space is put in place to allow future versions to inherit from new contracts
     * without impacting the fields within `RedemptionYield`.
     */
    uint256[500] private __inheritanceGap;

    /// @notice The CompoundV3 contract
    IComet public immutable COMPOUND;

    constructor(
        address _superstateToken,
        address _superstateTokenChainlinkFeedAddress,
        address _usdc,
        address _compound
    ) Redemption(_superstateToken, _superstateTokenChainlinkFeedAddress, _usdc) {
        COMPOUND = IComet(_compound);
    }

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
            (COMPOUND.balanceOf(address(this)) * FEE_DENOMINATOR) / (FEE_DENOMINATOR - redemptionFee);

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

        (uint256 usdcOutAmount,) = calculateUsdcOut(superstateTokenInAmount);

        if (COMPOUND.balanceOf(address(this)) < usdcOutAmount) revert InsufficientBalance();

        SUPERSTATE_TOKEN.safeTransferFrom({from: msg.sender, to: address(this), value: superstateTokenInAmount});
        COMPOUND.withdrawTo({to: msg.sender, asset: address(USDC), amount: usdcOutAmount});
        ISuperstateToken(address(SUPERSTATE_TOKEN)).offchainRedeem(superstateTokenInAmount);

        emit RedeemV2({
            redeemer: msg.sender,
            to: to,
            superstateTokenInAmount: superstateTokenInAmount,
            usdcOutAmount: usdcOutAmount
        });
    }

    /// @notice The ```withdraw``` function allows the owner to withdraw any type of ERC20
    /// @dev Requires msg.sender to be the owner address
    /// @dev If you specify the compound (cUSDC) address, you'll withdraw from compound and receive USDC, every other token works as expected.
    /// @dev Allows type(uint256).max withdraw from Compound when COMPOUND is the _token argument
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of `_token` to withdraw
    function withdraw(address _token, address to, uint256 amount) public override {
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

    /// @notice The ```deposit``` function transfer USDC from the caller to this contract and then to Compound v3 to accrue interest
    /// @dev Requires msg.sender to be the owner address
    /// @param usdcAmount amount of approved usdc to put into this contract / deposit in compound
    function deposit(uint256 usdcAmount) external {
        _checkOwner();
        if (usdcAmount == 0) revert BadArgs();

        USDC.safeTransferFrom({from: msg.sender, to: address(this), value: usdcAmount});
        USDC.approve({spender: address(COMPOUND), value: usdcAmount});
        COMPOUND.supply({asset: address(USDC), amount: usdcAmount});

        emit IRedemptionYield.Deposit({token: address(USDC), depositor: msg.sender, amount: usdcAmount});
    }
}
