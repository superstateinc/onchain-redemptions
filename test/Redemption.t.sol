// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Redemption} from "../src/Redemption.sol";
import {Oracle} from "./Oracle.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract RedemptionTest is Test {
    address public admin = address(this);

    address constant allowList = 0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149;
    address allowListAdmin = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;

    IERC20 constant USTB = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant _ustb_holder = 0xB8851D8fdd9a007A33f6b45BF602046644aBE81f;

    uint256 constant usdc_amount = 10_000_000_000_000;
    uint256 constant entity_id = 10_000_000_000_000;

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
        bytes memory data = abi.encodeWithSignature("setEntityIdForAddress(uint256,address)", entity_id, address(redemption));
        (bool success,) = address(USTB).call(data);
        require(success, "Setting perms failed");

        bytes memory data2 = abi.encodeWithSignature("setIsAllowed(uint256,bool)", entity_id, true);
        (bool success2,) = address(USTB).call(data2);
        require(success2, "Setting perms 2 failed");

        vm.stopPrank();
    }

    function testWithdraw() public {
        hoax(admin);
        redemption.withdraw(address(USDC), admin, usdc_amount);

        assertEq(USDC.balanceOf(admin), usdc_amount);

        hoax(admin);
        vm.expectRevert(bytes("Not enough balance"));
        redemption.withdraw(address(USDC), admin, 1);
    }

    function testWithdrawNotAdmin() public {
        hoax(_ustb_holder);
        vm.expectRevert(bytes("Not admin"));
        redemption.withdraw(address(USDC), admin, 1);
    }

    function testWithdrawAmountZero() public {
        hoax(admin);
        vm.expectRevert(bytes("TODO 1"));
        redemption.withdraw(address(USDC), admin, 0);
    }

    function testRedeem() public {
        assertEq(USDC.balanceOf(_ustb_holder), 0);

        uint256 ustbBalance = USTB.balanceOf(_ustb_holder);

        vm.startPrank(_ustb_holder);
        USDC.approve(address(redemption), ustbBalance);
        redemption.redeem(ustbBalance);
        vm.stopPrank();

        assertEq(USTB.balanceOf(_ustb_holder), 0);
        assertEq(USTB.balanceOf(address(redemption)), 0);

        // TODO: assert USDC amount in _ustb_holder


    }
}
