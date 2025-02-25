// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RedemptionIdleTestV1} from "test/v1/RedemptionIdleV1.t.sol";
import {RedemptionIdle} from "src/RedemptionIdle.sol";
import {IRedemptionV2} from "src/interfaces/IRedemptionV2.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";

contract RedemptionIdleTestV2 is RedemptionIdleTestV1 {
    RedemptionIdle public redemptionV2;

    function setUp() public override {
        // TODO: update test block number after deployment of new token contracts so tests pass
        super.setUp();

        redemptionV2 = new RedemptionIdle(address(SUPERSTATE_TOKEN), address(oracle), address(USDC));

        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV2), "");
    }

    function testRedeem() public override {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

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
        emit IRedemptionV2.Redeem({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999996
        });
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractUsdcBalance = USDC.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractUsdcBalance, redeemerUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractUsdcBalance, 4);
        assertEq(redemptionContractUsdcBalance, USDC_AMOUNT - redeemerUsdcBalance);
    }
}
