// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RedemptionYieldTestV2} from "test/v2/RedemptionYieldV2.t.sol";
import {RedemptionYield} from "src/RedemptionYield.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";
import {SuperstateOracle} from "src/oracle/SuperstateOracle.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

contract RedemptionYieldTestV3 is RedemptionYieldTestV2 {
    RedemptionYield public redemptionV3;
    address public constant SUPERSTATE_REDEMPTION_RECEIVER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public override {
        // TODO: update test block number after deployment of new token contracts so tests pass
        super.setUp();

        redemptionV3 = new RedemptionYield(address(SUPERSTATE_TOKEN), address(oracle), address(USDC), address(COMPOUND));

        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV3), "");
    }

    function testRedeem() public override {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();

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
            burner: address(redemption),
            src: address(redemption),
            amount: superstateTokenAmount
        });
        vm.expectEmit(true, true, true, true);
        // ~1e13, the original USDC amount
        emit IRedemption.RedeemV2({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_REDEMPTION_RECEIVER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999996
        });
        redemptionV3.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenAmount);
        vm.stopPrank();

        uint256 receiverUsdcBalance = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        uint256 redemptionContractCusdcBalance = COMPOUND.balanceOf(address(redemption));
        uint256 lostToRounding = 2;

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractCusdcBalance - lostToRounding, receiverUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractCusdcBalance, lostToRounding);
        assertEq(redemptionContractCusdcBalance, 4 - lostToRounding);
        assertEq(redemptionContractCusdcBalance, USDC_AMOUNT - receiverUsdcBalance - lostToRounding);
    }

    function testRedeemAmountTooLarge() public override {
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

        uint256 redeemerUstbBalanceBefore = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenRedeemAmount);
        redemptionV3.redeem(SUPERSTATE_REDEMPTION_RECEIVER, superstateTokenRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 receiverUsdcBalanceAfter = USDC.balanceOf(SUPERSTATE_REDEMPTION_RECEIVER);
        uint256 redemptionContractCusdcBalanceAfter = COMPOUND.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        // lose 0-3 because of rounding on compound side
        assertApproxEqAbs(
            receiverUsdcBalanceAfter,
            USDC_AMOUNT - redemptionContractCusdcBalanceAfter,
            3,
            "Redeemer has proper USDC balance"
        );
        assertApproxEqAbs(
            redemptionContractCusdcBalanceAfter,
            USDC_AMOUNT - receiverUsdcBalanceAfter,
            3,
            "Contract has proper USDC balance"
        );
    }

    function testCantRedeemPaused() public override {
        hoax(owner);
        redemption.pause();

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.redeem( 1);
    }

    function testRedeemWithFee() public override {
        uint256 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        (uint256 superstateTokenAmount,) = redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 receiverUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        assertEq(receiverUsdcBalance, 9_999_999_999_998);
    }
}
