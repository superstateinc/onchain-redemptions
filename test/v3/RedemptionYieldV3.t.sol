// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RedemptionYieldTestV2} from "test/v2/RedemptionYieldV2.t.sol";
import {RedemptionYield} from "src/RedemptionYield.sol";
import {IRedemptionYield} from "src/interfaces/IRedemptionYield.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";
import {SuperstateOracle} from "src/oracle/SuperstateOracle.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IRedemptionIdle} from "../../lib/ustb/lib/onchain-redemptions/src/interfaces/IRedemptionIdle.sol";

contract RedemptionYieldTestV3 is RedemptionYieldTestV2 {
    RedemptionYield public redemptionV3;
    address public constant SUPERSTATE_REDEMPTION_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public override {
        super.setUp();

        redemptionV3 =
            new RedemptionYield(address(SUPERSTATE_TOKEN), address(oracle), address(USDC), address(COMPOUND_ADDR));
        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV3), "");
        redemption = IRedemptionYield(address(redemptionProxy));
    }

    function testRedeem() public override {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);
        assertEq(USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER), 0);

        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();
        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, superstateTokenAmount);
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        // usdc balance * 1e6 (chainlink precision) * 1e6 (superstateToken precision) / feed price * 1e6 (usdc precision)
        // 1e13 * 1e6 / (real-time NAV/S price)
        assertEq(superstateTokenAmount, 963454067616);

        assertGe(superstateTokenBalance, superstateTokenAmount, "Don't redeem more than holder has");

        vm.startPrank(owner);
        redemption.pause();
        redemption.unpause();
        vm.stopPrank();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Transfer({
            from: SUPERSTATE_TOKEN_HOLDER,
            to: address(redemption),
            value: superstateTokenAmount
        });
        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.OffchainRedeem({
            burner: address(redemptionProxy),
            src: address(redemptionProxy),
            amount: superstateTokenAmount
        });
        vm.expectEmit(true, true, true, true);
        // ~1e13, the original USDC amount
        emit IRedemption.RedeemV3({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_REDEMPTION_RECEIVER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999996,
            usdcOutAmountWithFee: 9999999999996
        });
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractCusdcBalance = COMPOUND.balanceOf(address(redemption));
        uint256 lostToRounding = 1;
        uint256 additionalLoss = 2; // Account for the additional 2 tokens missing

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractCusdcBalance - lostToRounding - additionalLoss, redeemerUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractCusdcBalance, lostToRounding);
        assertEq(redemptionContractCusdcBalance, USDC_AMOUNT - redeemerUsdcBalance - lostToRounding - additionalLoss);
    }

    function testRedeemAmountTooLarge() public override {
        uint256 largeAmount = 10_000_000_000_000_000;
        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, largeAmount);
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        // Not enough USDC in the contract
        vm.expectRevert(IRedemption.InsufficientBalance.selector);
        redemptionV3.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeemAmountZeroFail() public override {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemptionV3.redeem(SUPERSTATE_REDEMPTION_RECEIVER, 0);
    }

    function testRedeemBadDataOldDataFail() public override {
        vm.warp(block.timestamp + 5 days + 1);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), 100);
        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemptionV3.redeem(SUPERSTATE_REDEMPTION_RECEIVER, 100);
        vm.stopPrank();
    }

    function testRedeemFuzz(uint256 superstateTokenRedeemAmount) public override {
        (uint256 maxRedemptionAmount,) = redemption.maxUstbRedemptionAmount();

        superstateTokenRedeemAmount = bound(superstateTokenRedeemAmount, 1, maxRedemptionAmount);
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, maxRedemptionAmount);
        deal(address(USDC), owner, USDC_AMOUNT);

        vm.startPrank(owner);
        USDC.approve(address(redemption), USDC_AMOUNT);
        redemption.deposit(USDC_AMOUNT);
        vm.stopPrank();

        uint256 redeemerUstbBalanceBefore = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionUsdcBalanceBefore = USDC.balanceOf(address(redemption));

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenRedeemAmount);
        redemption.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 receiverUsdcBalanceAfter = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        uint256 redemptionContractCusdcBalanceAfter = COMPOUND.balanceOf(address(redemption));
        uint256 redemptionUsdcBalanceAfter = USDC.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        assertEq(
            receiverUsdcBalanceAfter,
            redemptionUsdcBalanceBefore - redemptionUsdcBalanceAfter,
            "Redeemer received correct USDC amount"
        );

        // For cUSDC balance, just ensure it's substantial (without exact comparison)
        assertGe(
            redemptionContractCusdcBalanceAfter,
            USDC_AMOUNT, // Should be greater than initial deposit
            "Contract maintained sufficient Compound balance"
        );
    }

    function testCantRedeemPaused() public override {
        hoax(owner);
        redemption.pause();

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.redeem(1);
    }

    function testRedeemWithFee() public override {
        uint256 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();
        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, superstateTokenAmount);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 receiverUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        assertEq(receiverUsdcBalance, 9_999_999_999_988);
    }

    function testWithdraw() public virtual override {
        uint256 compoundBalance = COMPOUND.balanceOf(address(redemption));

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.Withdraw({token: address(USDC), withdrawer: owner, to: owner, amount: compoundBalance});

        redemption.withdraw(address(COMPOUND), owner, compoundBalance);

        // The remaining balance should be close to zero
        assertLe(COMPOUND.balanceOf(address(redemption)), 1);
    }
}
