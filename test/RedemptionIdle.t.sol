// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AllowList} from "ustb/src/AllowList.sol";
import {TestOracle} from "./TestOracle.sol";
import {RedemptionYield} from "../src/RedemptionYield.sol";
import {IUSTB} from "../src/IUSTB.sol";
import {IComet} from "../src/IComet.sol";
import {deployRedemptionIdle} from "../script/RedemptionIdle.s.sol";

contract RedemptionTest is Test {
    address public admin = address(this);

    AllowList constant allowList = AllowList(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149);
    address allowListAdmin = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;

    IERC20 constant USTB = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant USTB_HOLDER = 0xB8851D8fdd9a007A33f6b45BF602046644aBE81f;

    uint256 constant USDC_AMOUNT = 1e13;
    uint256 constant ENTITY_ID = 1;

    uint256 constant MAXIMUM_ORACLE_DELAY = 93_600;

    TestOracle public oracle;
    RedemptionYield public redemption;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_976_215);

        // roundId, answer, startedAt, updatedAt, answeredInRound
        oracle = new TestOracle(1, 10_192_577, 1_716_994_000, 1_716_994_030, 1);

        (address payable _address,,) = deployRedemptionIdle(
            admin, address(USTB), address(oracle), address(USDC), MAXIMUM_ORACLE_DELAY
        );

        redemption = RedemptionYield(_address);

        // 10 million
        deal(address(USDC), USTB_HOLDER, USDC_AMOUNT);

        hoax(USTB_HOLDER);
        USDC.transfer(address(redemption), USDC_AMOUNT);

        assertGe(USDC.balanceOf(address(redemption)), 0);

        vm.startPrank(allowListAdmin);
        allowList.setEntityIdForAddress(ENTITY_ID, address(redemption));
        vm.stopPrank();
    }

    function testMaxAmountWithdraw() public {
        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: USDC_AMOUNT});
        redemption.withdraw(address(USDC), admin, type(uint256).max);

        assertEq(0, USDC.balanceOf(address(redemption)), "No USDC in the redemption contract");
    }

    function testSendEtherFail() public {
        (bool success,) = address(redemption).call{value: 1}("");
        assertFalse(success);
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
        hoax(USTB_HOLDER);
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
        redemption.withdraw(address(USTB), admin, 1);
    }

    function testRedeemAmountTooLarge() public {
        uint256 ustbBalance = USTB.balanceOf(USTB_HOLDER);

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbBalance);
        // Not enough USDC in the contract
        vm.expectRevert(RedemptionYield.InsufficientBalance.selector);
        redemption.redeem(ustbBalance);
        vm.stopPrank();
    }

    function testRedeem() public {
        assertEq(USDC.balanceOf(USTB_HOLDER), 0);

        uint256 ustbBalance = USTB.balanceOf(USTB_HOLDER);
        uint256 ustbAmount = redemption.maxUstbRedemptionAmount();

        // usdc balance * 1e6 (chainlink precision) * 1e6 (ustb precision) / feed price * 1e6 (usdc precision)
        // 1e13 * 1e6 / 10192577
        assertEq(ustbAmount, 981106152055);

        assertGe(ustbBalance, ustbAmount, "Don't redeem more than holder has");

        vm.startPrank(admin);
        redemption.pause();
        redemption.unpause();
        vm.stopPrank();

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbAmount);
        vm.expectEmit(true, true, true, true);
        emit IUSTB.Transfer({from: USTB_HOLDER, to: address(redemption), value: ustbAmount});
        vm.expectEmit(true, true, true, true);
        emit IUSTB.Burn({burner: address(redemption), from: address(redemption), amount: ustbAmount});
        vm.expectEmit(true, true, true, true);
        // ~1e13, the original USDC amount
        emit RedemptionYield.Redeem({redeemer: USTB_HOLDER, ustbInAmount: ustbAmount, usdcOutAmount: 9999999999994});
        redemption.redeem(ustbAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(USTB_HOLDER);
        uint256 redemptionContractUsdcBalance = USDC.balanceOf(address(redemption));

        assertEq(USTB.balanceOf(USTB_HOLDER), ustbBalance - ustbAmount);
        assertEq(USDC_AMOUNT - redemptionContractUsdcBalance, redeemerUsdcBalance);

        assertEq(USTB.balanceOf(address(redemption)), 0);

        assertEq(redemptionContractUsdcBalance, 6);
        assertEq(redemptionContractUsdcBalance, USDC_AMOUNT - redeemerUsdcBalance);
    }

    function testRedeemFuzz(uint256 ustbRedeemAmount) public {
        uint256 maxRedemptionAmount = redemption.maxUstbRedemptionAmount();

        ustbRedeemAmount = bound(ustbRedeemAmount, 1, maxRedemptionAmount);

        assertEq(USDC.balanceOf(USTB_HOLDER), 0);

        uint256 redeemerUstbBalanceBefore = USTB.balanceOf(USTB_HOLDER);

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbRedeemAmount);
        redemption.redeem(ustbRedeemAmount);
        vm.stopPrank();

        uint256 redeemerUstbBalanceAfter = USTB.balanceOf(USTB_HOLDER);
        uint256 redeemerUsdcBalanceAfter = USDC.balanceOf(USTB_HOLDER);
        uint256 redemptionContractUsdcBalanceAfter = USDC.balanceOf(address(redemption));

        assertEq(USTB.balanceOf(address(redemption)), 0, "Contract has 0 USTB balance");

        assertEq(
            redeemerUstbBalanceAfter, redeemerUstbBalanceBefore - ustbRedeemAmount, "Redeemer has proper USTB balance"
        );

        assertEq(redeemerUsdcBalanceAfter, USDC_AMOUNT - redemptionContractUsdcBalanceAfter, "Redeemer has proper USDC balance");
        assertEq(redemptionContractUsdcBalanceAfter, USDC_AMOUNT - redeemerUsdcBalanceAfter, "Contract has proper USDC balance");
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

        assertEq(USDC.balanceOf(USTB_HOLDER), 0);

        uint256 ustbAmount = redemption.maxUstbRedemptionAmount();

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbAmount);
        vm.expectRevert(RedemptionYield.BadChainlinkData.selector);
        redemption.redeem(ustbAmount);
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

        assertEq(USDC.balanceOf(USTB_HOLDER), 0);

        uint256 ustbBalance = USTB.balanceOf(USTB_HOLDER);

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbBalance);
        redemption.redeem(ustbBalance);
        vm.stopPrank();
    }

    function testRedeemBadDataOldDataFail() public {
        vm.warp(block.timestamp + MAXIMUM_ORACLE_DELAY);

        assertEq(USDC.balanceOf(USTB_HOLDER), 0);

        uint256 ustbBalance = USTB.balanceOf(USTB_HOLDER);
        uint256 ustbAmount = redemption.maxUstbRedemptionAmount();

        assertGe(ustbBalance, ustbAmount, "Don't redeem more than holder has");

        vm.startPrank(USTB_HOLDER);
        USTB.approve(address(redemption), ustbAmount);
        vm.expectRevert(RedemptionYield.BadChainlinkData.selector);
        redemption.redeem(ustbAmount);
        vm.stopPrank();
    }

    function testRedeemAmountZeroFail() public {
        hoax(USTB_HOLDER);
        vm.expectRevert(RedemptionYield.BadArgs.selector);
        redemption.redeem(0);
    }

    function testAdminSetOracleDelay() public {
        uint256 newDelay = 1234567;

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit RedemptionYield.SetMaximumOracleDelay({oldMaxOracleDelay: MAXIMUM_ORACLE_DELAY, newMaxOracleDelay: newDelay});
        redemption.setMaximumOracleDelay(newDelay);

        assertEq(newDelay, redemption.maximumOracleDelay());
    }

    function testNonAdminSetOracleDelayFail() public {
        uint256 newDelay = 1234567;

        hoax(USTB_HOLDER);
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

        hoax(USTB_HOLDER);
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