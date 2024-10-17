// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AllowList} from "ustb/src/AllowList.sol";
import {TestChainlinkDataFeedOracle} from "./TestChainlinkDataFeedOracle.sol";
import {RedemptionYield} from "../src/RedemptionYield.sol";
import {ISuperstateToken} from "../src/ISuperstateToken.sol";
import {IComet} from "../src/IComet.sol";
import {deployRedemptionYield} from "../script/RedemptionYield.s.sol";

contract RedemptionYieldTest is Test {
    address public admin = address(this);

    AllowList constant allowList = AllowList(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149);
    address allowListAdmin = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;

    IERC20 constant SUPERSTATE_TOKEN = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IComet constant COMPOUND = IComet(0xc3d688B66703497DAA19211EEdff47f25384cdc3);
    address constant SUPERSTATE_TOKEN_HOLDER = 0xB8851D8fdd9a007A33f6b45BF602046644aBE81f;

    uint256 constant USDC_AMOUNT = 1e13;
    uint256 constant ENTITY_ID = 1;

    uint256 constant MAXIMUM_ORACLE_DELAY = 93_600;

    TestChainlinkDataFeedOracle public oracle;
    RedemptionYield public redemption;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_976_215);

        // roundId, answer, startedAt, updatedAt, answeredInRound
        oracle = new TestChainlinkDataFeedOracle(1, 10_192_577, 1_716_994_000, 1_716_994_030, 1);

        (address payable _address,,) = deployRedemptionYield(
            admin, address(SUPERSTATE_TOKEN), address(oracle), address(USDC), MAXIMUM_ORACLE_DELAY, address(COMPOUND)
        );
        redemption = RedemptionYield(_address);

        vm.startPrank(allowListAdmin);
        allowList.setEntityIdForAddress(ENTITY_ID, address(redemption));

        vm.stopPrank();

        deal(address(USDC), admin, USDC_AMOUNT);

        vm.startPrank(admin);
        USDC.approve(address(redemption), USDC_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Deposit({token: address(USDC), depositor: admin, amount: USDC_AMOUNT});
        redemption.deposit(USDC_AMOUNT);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(redemption)), 0);
        assertGt(COMPOUND.balanceOf(address(redemption)), 0);
    }

    function testDepositUnauthorized() public {
        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        USDC.approve(address(redemption), 0);
        vm.expectRevert(RedemptionYield.Unauthorized.selector);
        redemption.deposit(0);
        vm.stopPrank();
    }

    function testDepositBadArgs() public {
        vm.startPrank(admin);
        USDC.approve(address(redemption), 0);
        vm.expectRevert(RedemptionYield.BadArgs.selector);
        redemption.deposit(0);
        vm.stopPrank();
    }

    function testInterestWithdraw() public {
        uint256 initialBalance = COMPOUND.balanceOf(address(redemption));
        uint256 ts = block.timestamp;

        vm.roll(19_976_215 + 5_000);
        vm.warp(ts + (5_000 * 12));

        COMPOUND.accrueAccount(address(redemption));

        uint256 interestBalance = COMPOUND.balanceOf(address(redemption));

        assertGt(interestBalance, initialBalance, "Interest accrues over time");

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: interestBalance});
        redemption.withdraw(address(COMPOUND), admin, interestBalance);

        assertEq(0, USDC.balanceOf(address(redemption)), "No USDC in the redemption contract");
        assertEq(interestBalance, USDC.balanceOf(admin), "USDC balance + interest went to admin");
    }

    function testMaxAmountWithdraw() public {
        uint256 initialBalance = COMPOUND.balanceOf(address(redemption));
        uint256 ts = block.timestamp;

        vm.roll(19_976_215 + 5_000);
        vm.warp(ts + (5_000 * 12));

        COMPOUND.accrueAccount(address(redemption));

        uint256 interestBalance = COMPOUND.balanceOf(address(redemption));

        assertGt(interestBalance, initialBalance, "Interest accrues over time");

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: interestBalance});
        redemption.withdraw(address(COMPOUND), admin, type(uint256).max);

        assertEq(0, USDC.balanceOf(address(redemption)), "No USDC in the redemption contract");
        assertEq(interestBalance, USDC.balanceOf(admin), "USDC balance + interest went to admin");
    }

    function testSendEtherFail() public {
        (bool success,) = address(redemption).call{value: 1}("");
        assertFalse(success);
    }

    function testWithdraw() public {
        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: USDC_AMOUNT - 1});
        redemption.withdraw(address(COMPOUND), admin, USDC_AMOUNT - 1);

        assertEq(USDC.balanceOf(admin), USDC_AMOUNT - 1);
    }

    function testWithdrawUsdc() public {
        deal(address(USDC), address(redemption), USDC_AMOUNT);

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: USDC_AMOUNT});
        redemption.withdraw(address(USDC), admin, USDC_AMOUNT);

        assertEq(USDC.balanceOf(admin), USDC_AMOUNT);
    }

    function testWithdrawNotAdmin() public {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(RedemptionYield.Unauthorized.selector);
        redemption.withdraw(address(USDC), admin, 1);
    }

    function testWithdrawAmountZero() public {
        hoax(admin);
        vm.expectRevert(RedemptionYield.BadArgs.selector);
        redemption.withdraw(address(USDC), admin, 0);
    }

    function testWithdrawBalanceZero() public {
        hoax(admin);
        vm.expectRevert(RedemptionYield.InsufficientBalance.selector);
        redemption.withdraw(address(SUPERSTATE_TOKEN), admin, 1);
    }

    function testRedeemAmountTooLarge() public {
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        // Not enough USDC in the contract
        vm.expectRevert(RedemptionYield.InsufficientBalance.selector);
        redemption.redeem(superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeem() public {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 superstateTokenAmount = redemption.maxUstbRedemptionAmount();

        // usdc balance * 1e6 (chainlink precision) * 1e6 (superstateToken precision) / feed price * 1e6 (usdc precision)
        // 1e13 * 1e6 / 10192577
        assertEq(superstateTokenAmount, 981106152055);

        assertGe(superstateTokenBalance, superstateTokenAmount, "Don't redeem more than holder has");

        vm.startPrank(admin);
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
        emit ISuperstateToken.Burn({
            burner: address(redemption),
            from: address(redemption),
            amount: superstateTokenAmount
        });
        vm.expectEmit(true, true, true, true);
        // ~1e13, the original USDC amount
        emit RedemptionYield.Redeem({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999994
        });
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractCusdcBalance = COMPOUND.balanceOf(address(redemption));
        uint256 lostToRounding = 2;

        assertEq(SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER), superstateTokenBalance - superstateTokenAmount);
        assertEq(USDC_AMOUNT - redemptionContractCusdcBalance - lostToRounding, redeemerUsdcBalance);

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractCusdcBalance, 6 - lostToRounding);
        assertEq(redemptionContractCusdcBalance, USDC_AMOUNT - redeemerUsdcBalance - lostToRounding);
    }

    function testRedeemFuzz(uint256 superstateTokenRedeemAmount) public {
        uint256 maxRedemptionAmount = redemption.maxUstbRedemptionAmount();

        superstateTokenRedeemAmount = bound(superstateTokenRedeemAmount, 1, maxRedemptionAmount);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 redeemerUstbBalanceBefore = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenRedeemAmount);
        redemption.redeem(superstateTokenRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redeemerUsdcBalanceAfter = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 redemptionContractCusdcBalanceAfter = COMPOUND.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        // lose 0-3 because of rounding on compound side
        assertApproxEqAbs(
            redeemerUsdcBalanceAfter,
            USDC_AMOUNT - redemptionContractCusdcBalanceAfter,
            3,
            "Redeemer has proper USDC balance"
        );
        assertApproxEqAbs(
            redemptionContractCusdcBalanceAfter,
            USDC_AMOUNT - redeemerUsdcBalanceAfter,
            3,
            "Contract has proper USDC balance"
        );
    }

    function testRedeemBadDataLowPriceFail() public {
        (uint80 _roundId,, uint256 _startedAt, uint256 _updatedAt,) = oracle.latestRoundData();
        oracle.update({
            _roundId: _roundId + 1,
            _answer: 6_999_999,
            _startedAt: _startedAt + 86_400,
            _updatedAt: _updatedAt + 86_400,
            _answeredInRound: _roundId + 1
        });

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenAmount = redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        vm.expectRevert(RedemptionYield.BadChainlinkData.selector);
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();
    }

    function testRedeemMinimumPrice() public {
        vm.warp(block.timestamp + 86_400);

        (uint80 _roundId,,,,) = oracle.latestRoundData();
        oracle.update({
            _roundId: _roundId + 1,
            _answer: 7_000_000,
            _startedAt: block.timestamp,
            _updatedAt: block.timestamp,
            _answeredInRound: _roundId + 1
        });

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        redemption.redeem(superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeemBadDataOldDataFail() public {
        vm.warp(block.timestamp + MAXIMUM_ORACLE_DELAY);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 superstateTokenAmount = redemption.maxUstbRedemptionAmount();

        assertGe(superstateTokenBalance, superstateTokenAmount, "Don't redeem more than holder has");

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        vm.expectRevert(RedemptionYield.BadChainlinkData.selector);
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();
    }

    function testRedeemAmountZeroFail() public {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(RedemptionYield.BadArgs.selector);
        redemption.redeem(0);
    }

    function testAdminSetOracleDelay() public {
        uint256 newDelay = 1234567;

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.SetMaximumOracleDelay({
            oldMaxOracleDelay: MAXIMUM_ORACLE_DELAY,
            newMaxOracleDelay: newDelay
        });
        redemption.setMaximumOracleDelay(newDelay);

        assertEq(newDelay, redemption.maximumOracleDelay());
    }

    function testNonAdminSetOracleDelayFail() public {
        uint256 newDelay = 1234567;

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(RedemptionYield.Unauthorized.selector);
        redemption.setMaximumOracleDelay(newDelay);
    }

    function testAdminSetOracleDelaySameFail() public {
        uint256 oldDelay = redemption.maximumOracleDelay();

        hoax(admin);
        vm.expectRevert(RedemptionYield.BadArgs.selector);
        redemption.setMaximumOracleDelay(oldDelay);
    }

    function testCantRedeemPaused() public {
        hoax(admin);
        redemption.pause();

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.redeem(1);
    }

    function testCantPauseAlreadyPaused() public {
        hoax(admin);
        redemption.pause();

        hoax(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.pause();
    }

    function testCantUnpauseAlreadyUnpaused() public {
        hoax(admin);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        redemption.unpause();
    }
}
