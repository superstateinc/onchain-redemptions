// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Redemption} from "../src/Redemption.sol";
import {IUSTB} from "../src/IUSTB.sol";
import {Oracle} from "./Oracle.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AllowList} from "ustb/src/AllowList.sol";

contract RedemptionTest is Test {
    address public admin = address(this);

    AllowList constant allowList = AllowList(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149);
    address allowListAdmin = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;

    IERC20 constant USTB = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant _ustb_holder = 0xB8851D8fdd9a007A33f6b45BF602046644aBE81f;

    uint256 constant usdc_amount = 10_000_000_000_000;
    uint256 constant entity_id = 1;

    Oracle public oracle;
    Redemption public redemption;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_976_215);

        oracle = new Oracle();
        redemption = new Redemption(admin, address(USTB), address(oracle), address(USDC));

        // 10 million
        deal(address(USDC), _ustb_holder, usdc_amount);

        hoax(_ustb_holder);
        USDC.transfer(address(redemption), usdc_amount);

        assertGe(USDC.balanceOf(address(redemption)), 0);

        vm.startPrank(allowListAdmin);
        allowList.setEntityIdForAddress(entity_id, address(redemption));

        vm.stopPrank();
    }

    function testSendEtherFail() public {
        (bool success,) = address(redemption).call{value: 1}("");
        assertFalse(success);
    }

    function testWithdraw() public {
        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit Redemption.Withdraw({token: address(USDC), withdrawer: admin, to: admin, amount: usdc_amount});
        redemption.withdraw(address(USDC), admin, usdc_amount);

        assertEq(USDC.balanceOf(admin), usdc_amount);
    }

    function testWithdrawNotAdmin() public {
        hoax(_ustb_holder);
        vm.expectRevert(Redemption.Unauthorized.selector);
        redemption.withdraw(address(USDC), admin, 1);
    }

    function testWithdrawAmountZero() public {
        hoax(admin);
        vm.expectRevert(Redemption.BadArgs.selector);
        redemption.withdraw(address(USDC), admin, 0);
    }

    function testWithdrawBalanceZero() public {
        hoax(admin);
        vm.expectRevert(Redemption.InsufficientBalance.selector);
        redemption.withdraw(address(USTB), admin, 1);
    }

    function testRedeemAmountTooLarge() public {
        uint256 ustbBalance = USTB.balanceOf(_ustb_holder);

        vm.startPrank(_ustb_holder);
        USTB.approve(address(redemption), ustbBalance);
        // Not enough USDC in the contract
        vm.expectRevert(Redemption.InsufficientBalance.selector);
        redemption.redeem(ustbBalance);
        vm.stopPrank();
    }

    function testRedeem() public {
        assertEq(USDC.balanceOf(_ustb_holder), 0);

        uint256 ustbBalance = USTB.balanceOf(_ustb_holder);
        uint256 ustbAmount = redemption.maxUstbRedemptionAmount();

        assertGe(ustbBalance, ustbAmount, "Don't redeem more than holder has");

        vm.startPrank(_ustb_holder);
        USTB.approve(address(redemption), ustbAmount);
        vm.expectEmit(true, true, true, true);
        emit IUSTB.Transfer({from: _ustb_holder, to: address(redemption), value: ustbAmount});
        vm.expectEmit(true, true, true, true);
        emit IUSTB.Burn({burner: address(redemption), from: address(redemption), amount: ustbAmount});
        vm.expectEmit(true, true, true, true);
        emit Redemption.Redemption({redeemer: _ustb_holder, ustbInAmount: ustbAmount, usdcOutAmount: 9999999999994});
        redemption.redeem(ustbAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(_ustb_holder);

        assertEq(USTB.balanceOf(_ustb_holder), ustbBalance - ustbAmount);
        assertEq(usdc_amount - USDC.balanceOf(address(redemption)), redeemerUsdcBalance);

        assertEq(USTB.balanceOf(address(redemption)), 0);
        assertEq(USDC.balanceOf(address(redemption)), 6);
        assertEq(USDC.balanceOf(address(redemption)), usdc_amount - redeemerUsdcBalance);
    }

    // TODO: more amount redeem tests / fuzz it

    // TODO: bad data / StaleChainlinkData

    function testRedeemAmountZeroFail() public {
        uint256 ustbBalance = USTB.balanceOf(_ustb_holder);

        hoax(_ustb_holder);
        vm.expectRevert(Redemption.BadArgs.selector);
        redemption.redeem(0);
    }

    function testAdminSetOracleDelay() public {
        uint256 newDelay = 1234567;

        hoax(admin);
        vm.expectEmit(true, true, true, true);
        emit Redemption.SetMaximumOracleDelay({oldMaxOracleDelay: 100_800, newMaxOracleDelay: newDelay});
        redemption.setMaximumOracleDelay(newDelay);

        assertEq(newDelay, redemption.maximumOracleDelay());
    }

    function testNonAdminSetOracleDelayFail() public {
        uint256 newDelay = 1234567;

        hoax(_ustb_holder);
        vm.expectRevert(Redemption.Unauthorized.selector);
        redemption.setMaximumOracleDelay(newDelay);
    }

    function testAdminSetOracleDelaySameFail() public {
        uint256 oldDelay = redemption.maximumOracleDelay();

        hoax(admin);
        vm.expectRevert(Redemption.BadArgs.selector);
        redemption.setMaximumOracleDelay(oldDelay);
    }
}
