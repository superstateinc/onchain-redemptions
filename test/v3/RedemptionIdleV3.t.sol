// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RedemptionIdleTestV2} from "test/v2/RedemptionIdleV2.t.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";
import {RedemptionIdle} from "src/RedemptionIdle.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {SuperstateOracle} from "src/oracle/SuperstateOracle.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IRedemptionIdle} from "src/interfaces/IRedemptionIdle.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract RedemptionIdleTestV3 is RedemptionIdleTestV2 {
    RedemptionIdle public redemptionV3;
    address public constant SUPERSTATE_REDEMPTION_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public override {
        super.setUp();

        redemptionV3 = new RedemptionIdle(address(SUPERSTATE_TOKEN), address(oracle), address(USDC));
        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV3), "");
        redemption = IRedemptionIdle(address(redemptionProxy));
    }

    function testRedeem() public override {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);
        assertEq(USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();

        // usdc balance * 1e6 (chainlink precision) * 1e6 (superstateToken precision) / feed price * 1e6 (usdc precision)
        // 1e13 * 1e6 / 10,379,322(real-time NAV/S price)
        assertEq(superstateTokenAmount, 963454067616);

        assertGe(superstateTokenBalance, superstateTokenAmount, "Don't redeem more than holder has");

        vm.startPrank(owner);
        redemption.pause();
        redemption.unpause();
        vm.stopPrank();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);

        vm.expectEmit(true, true, true, true, address(SUPERSTATE_TOKEN));
        emit ISuperstateToken.Transfer({
            from: SUPERSTATE_TOKEN_HOLDER,
            to: address(redemption),
            value: superstateTokenAmount
        });

        vm.expectEmit(true, true, true, true, address(USDC));
        emit IERC20.Transfer({from: address(redemption), to: SUPERSTATE_REDEMPTION_RECEIVER, value: 9999999999996});

        vm.expectEmit(true, true, true, true, address(SUPERSTATE_TOKEN));
        emit ISuperstateToken.Transfer({from: address(redemption), to: address(0), value: superstateTokenAmount});

        vm.expectEmit(true, true, true, true, address(SUPERSTATE_TOKEN));
        emit ISuperstateToken.OffchainRedeem({
            burner: address(redemptionProxy),
            src: address(redemptionProxy),
            amount: superstateTokenAmount
        });

        vm.expectEmit(true, true, true, true, address(redemption));
        //this is performed without fee, thus the amount is expected to be the same
        //see testRedeemWithFee for fee event diff
        emit IRedemption.RedeemV2({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_REDEMPTION_RECEIVER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmountAfterFee: 9999999999996,
            usdcOutAmountBeforeFee: 9999999999996
        });

        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenAmount);
        vm.stopPrank();

        uint256 receiverUsdcBalance = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        uint256 redemptionContractUsdcBalance = USDC.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractUsdcBalance, receiverUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractUsdcBalance, 4);
        assertEq(redemptionContractUsdcBalance, USDC_AMOUNT - receiverUsdcBalance);
    }

    function testRedeemAmountTooLarge() public override {
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        // Not enough USDC in the contract
        vm.expectRevert(IRedemption.InsufficientBalance.selector);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeemAmountZeroFail() public override {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, 0);
    }

    function testRedeemBadDataOldDataFail() public override {
        vm.warp(block.timestamp + 5 days + 1);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), 100);
        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, 100);
        vm.stopPrank();
    }

    function testRedeemFuzz(uint256 superstateTokenRedeemAmount) public override {
        (uint256 maxRedemptionAmount,) = redemption.maxUstbRedemptionAmount();

        superstateTokenRedeemAmount = bound(superstateTokenRedeemAmount, 1, maxRedemptionAmount);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 redeemerUstbBalanceBefore = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenRedeemAmount);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 receiverUsdcBalanceAfter = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        uint256 redemptionContractUsdcBalanceAfter = USDC.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        assertEq(
            receiverUsdcBalanceAfter,
            USDC_AMOUNT - redemptionContractUsdcBalanceAfter,
            "Receiver has proper USDC balance"
        );
        assertEq(
            redemptionContractUsdcBalanceAfter,
            USDC_AMOUNT - receiverUsdcBalanceAfter,
            "Contract has proper USDC balance"
        );
    }

    function testCantRedeemPaused() public override {
        hoax(owner);
        redemption.pause();

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, 1);
    }

    function testRedeemWithFee() public override {
        uint256 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();

        
        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        vm.expectEmit(true, true, true, true, address(redemption));
        //this is performed with fee
        emit IRedemption.RedeemV2({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_REDEMPTION_RECEIVER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmountAfterFee: 9999999999998,
            usdcOutAmountBeforeFee: 10005002501248
        });
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        assertEq(redeemerUsdcBalance, 9_999_999_999_998);
    }
}
