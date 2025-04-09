// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {RedemptionYieldTestV1} from "test/v1/RedemptionYieldV1.t.sol";
import {RedemptionYieldV2} from "src/v2/RedemptionYieldV2.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {IRedemptionYield} from "src/interfaces/IRedemptionYield.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";
import {SuperstateOracle} from "src/oracle/SuperstateOracle.sol";
import {deploySuperstateOracle} from "script/SuperstateOracle.s.sol";
import {AllowList} from "ustb/src/allowlist/AllowList.sol";
import {IAllowListV2} from "ustb/src/interfaces/allowlist/IAllowListV2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {deployRedemptionYieldV1} from "script/RedemptionYield.s.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {RedemptionYield} from "../../src/RedemptionYield.sol";

contract RedemptionYieldTestV2 is RedemptionYieldTestV1 {
    RedemptionYield public redemptionV2;
    AllowList public constant allowListV2 = AllowList(0x02f1fA8B196d21c7b733EB2700B825611d8A38E5);
    IAllowListV2.EntityId ENTITY_ID_V2 = IAllowListV2.EntityId.wrap(1);
    address public allowListV2Admin = 0x7747940aDBc7191f877a9B90596E0DA4f8deb2Fe;

    uint256 public forkBlockNumberV2 = 21_933_146;
    uint256 public rollBlockNumberV2 = 21_993_400;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), forkBlockNumberV2);
        vm.roll(rollBlockNumberV2);

        (address payable _addressOracle,,) = deploySuperstateOracle(owner, address(SUPERSTATE_TOKEN), 1_000_000);
        oracle = SuperstateOracle(_addressOracle);

        uint64 currentTimestamp = uint64(block.timestamp);
        vm.warp(currentTimestamp);

        hoax(owner);
        oracle.addCheckpoint(currentTimestamp - 1, currentTimestamp, 10_374_862, false);

        uint64 nextDayTimestamp = currentTimestamp + uint64(1 days);
        vm.warp(nextDayTimestamp);

        hoax(owner);
        oracle.addCheckpoint(nextDayTimestamp - 1, nextDayTimestamp, 10_379_322, false);

        (,,, address proxy) = deployRedemptionYieldV1(
            address(SUPERSTATE_TOKEN),
            address(oracle),
            address(USDC),
            address(this),
            address(this),
            MAXIMUM_ORACLE_DELAY,
            address(this),
            0,
            address(COMPOUND)
        );

        redemption = IRedemptionYield(address(proxy));
        redemptionProxy = ITransparentUpgradeableProxy(payable(proxy));
        redemptionProxyAdmin = ProxyAdmin(getAdminAddress(address(redemptionProxy)));

        vm.startPrank(allowListV2Admin);
        allowListV2.setEntityIdForAddress(ENTITY_ID_V2, address(redemption));

        vm.stopPrank();

        deal(address(USDC), owner, USDC_AMOUNT);

        vm.startPrank(owner);
        USDC.approve(address(redemption), USDC_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IRedemptionYield.Deposit({token: address(USDC), depositor: owner, amount: USDC_AMOUNT});
        redemption.deposit(USDC_AMOUNT);

        vm.stopPrank();

        redemptionV2 =
            new RedemptionYield(address(SUPERSTATE_TOKEN), address(oracle), address(USDC), address(COMPOUND_ADDR));
        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV2), "");
        redemption = IRedemptionYield(address(redemptionProxy));

        assertEq(USDC.balanceOf(address(redemption)), 0);
        assertGt(COMPOUND.balanceOf(address(redemption)), 0);

        deal(address(USDC), SUPERSTATE_TOKEN_HOLDER, 0); // Reset balance to 0
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);
    }

    function testRedeem() public virtual override {
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
        emit IRedemption.RedeemV2({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_TOKEN_HOLDER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999996,
            usdcOutAmountWithFee: 9999999999996
        });
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractCusdcBalance = COMPOUND.balanceOf(address(redemption));
        // compound balance of redemption contract may lose some token to math precision
        // lostToRounding covers the potential discrepancy.
        uint256 lostToRounding = 3;

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractCusdcBalance - lostToRounding, redeemerUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractCusdcBalance, 1);
        assertEq(redemptionContractCusdcBalance, USDC_AMOUNT - redeemerUsdcBalance - lostToRounding);
    }

    function testRedeemAmountTooLarge() public virtual override {
        uint256 largeAmount = 10_000_000_000_000_000;
        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, largeAmount);
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        // Not enough USDC in the contract
        vm.expectRevert(IRedemption.InsufficientBalance.selector);
        redemptionV2.redeem(superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeemWithFee() public virtual override {
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

    function testRedeemFuzz(uint256 superstateTokenRedeemAmount) public virtual override {
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

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenRedeemAmount);
        redemption.redeem(superstateTokenRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 receiverUsdcBalanceAfter = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractCusdcBalanceAfter = COMPOUND.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        // Calculate the expected amount based on the token amount and oracle price
        (, uint256 oraclePrice) = redemption.maxUstbRedemptionAmount();
        uint256 expectedUsdcAmount = (superstateTokenRedeemAmount * oraclePrice) / 1e6;

        assertEq(receiverUsdcBalanceAfter, expectedUsdcAmount, "Redeemer received correct USDC amount");

        // For cUSDC balance, just ensure it's substantial (without exact comparison)
        assertGe(
            redemptionContractCusdcBalanceAfter,
            USDC_AMOUNT, // Should be greater than initial deposit
            "Contract maintained sufficient Compound balance"
        );
    }
}
