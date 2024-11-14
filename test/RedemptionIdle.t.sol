// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AllowList} from "ustb/src/AllowList.sol";
import {Redemption} from "../src/Redemption.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {IRedemptionIdle} from "src/interfaces/IRedemptionIdle.sol";
import {ISuperstateToken} from "../src/ISuperstateToken.sol";
import {IComet} from "../src/IComet.sol";
import {deployRedemptionIdle} from "../script/RedemptionIdle.s.sol";
import {SuperstateOracle} from "../src/oracle/SuperstateOracle.sol";
import {deploySuperstateOracle} from "../script/SuperstateOracle.s.sol";

contract RedemptionIdleTest is Test {
    address public owner = address(this);

    AllowList public constant allowList = AllowList(0x42d75C8FdBBF046DF0Fe1Ff388DA16fF99dE8149);
    address public allowListAdmin = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;

    IERC20 public constant SUPERSTATE_TOKEN = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant SUPERSTATE_TOKEN_HOLDER = 0xB8851D8fdd9a007A33f6b45BF602046644aBE81f;

    uint256 public constant USDC_AMOUNT = 1e13;
    uint256 public constant ENTITY_ID = 1;

    uint256 public constant MAXIMUM_ORACLE_DELAY = 93_600;

    SuperstateOracle public oracle;
    IRedemptionIdle public redemption;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19_976_215);
        vm.roll(20_993_400);

        (address payable _addressOracle,,) = deploySuperstateOracle(owner, address(SUPERSTATE_TOKEN), 1_000_000);

        oracle = SuperstateOracle(_addressOracle);

        vm.warp(1726_779_601);

        hoax(owner);
        oracle.addCheckpoint(1726779600, 1726779601, 10_374_862, false);

        vm.warp(1726866001);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_379_322, false);
        // result = laterCheckpointNavs + ((laterCheckpointNavs - earlierCheckpointNavs) * (targetTimestamp - laterCheckpointTimestamp)) / (laterCheckpointTimestamp - earlierCheckpointTimestamp)

        // 4460 diff between navs = 1726866000 - 1726779600
        // 86,400 seconds between checkpoints
        // diff between
        // 10379322 + 4460* 1 / 86,400 = 10,379,322 interpolated nav/s

        (,,, address proxy) = deployRedemptionIdle(
            address(SUPERSTATE_TOKEN),
            address(oracle),
            address(USDC),
            address(this),
            address(this),
            MAXIMUM_ORACLE_DELAY,
            address(this),
            0
        );

        redemption = IRedemptionIdle(address(proxy));

        // 10 million
        deal(address(USDC), SUPERSTATE_TOKEN_HOLDER, USDC_AMOUNT);

        hoax(SUPERSTATE_TOKEN_HOLDER);
        USDC.transfer(address(redemption), USDC_AMOUNT);

        assertGe(USDC.balanceOf(address(redemption)), 0);

        vm.startPrank(allowListAdmin);
        allowList.setEntityIdForAddress(ENTITY_ID, address(redemption));
        vm.stopPrank();
    }

    function testSendEtherFail() public {
        (bool success,) = address(redemption).call{value: 1}("");
        assertFalse(success);
    }

    function testWithdrawUsdc() public {
        deal(address(USDC), address(redemption), USDC_AMOUNT);

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.Withdraw({token: address(USDC), withdrawer: owner, to: owner, amount: USDC_AMOUNT});
        redemption.withdraw(address(USDC), owner, USDC_AMOUNT);

        assertEq(USDC.balanceOf(owner), USDC_AMOUNT);
    }

    function testWithdrawToSweepUsdc() public {
        deal(address(USDC), address(redemption), USDC_AMOUNT);

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.Withdraw({token: address(USDC), withdrawer: owner, to: owner, amount: USDC_AMOUNT});
        redemption.withdrawToSweepDestination(USDC_AMOUNT);

        assertEq(USDC.balanceOf(address(this)), USDC_AMOUNT);
    }

    function testWithdrawNotAdmin() public {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, SUPERSTATE_TOKEN_HOLDER));
        redemption.withdraw(address(USDC), owner, 1);
    }

    function testWithdrawAmountZero() public {
        hoax(owner);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.withdraw(address(USDC), owner, 0);
    }

    function testWithdrawBalanceZero() public {
        hoax(owner);
        vm.expectRevert(IRedemption.InsufficientBalance.selector);
        redemption.withdraw(address(SUPERSTATE_TOKEN), owner, 1);
    }

    function testRedeemAmountTooLarge() public {
        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenBalance);
        // Not enough USDC in the contract
        vm.expectRevert(IRedemption.InsufficientBalance.selector);
        redemption.redeem(superstateTokenBalance);
        vm.stopPrank();
    }

    function testRedeem() public {
        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        uint256 superstateTokenBalance = SUPERSTATE_TOKEN.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        uint256 superstateTokenAmount = redemption.maxUstbRedemptionAmount();

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
        emit ISuperstateToken.Burn({
            burner: address(redemption),
            from: address(redemption),
            amount: superstateTokenAmount
        });
        vm.expectEmit(true, true, true, true);
        // ~1e13, the original USDC amount
        emit IRedemption.Redeem({
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
        uint256 redemptionContractUsdcBalanceAfter = USDC.balanceOf(address(redemption));

        assertEq(SUPERSTATE_TOKEN.balanceOf(address(redemption)), 0, "Contract has 0 SUPERSTATE_TOKEN balance");

        assertEq(
            redeemerUstbBalanceAfter,
            redeemerUstbBalanceBefore - superstateTokenRedeemAmount,
            "Redeemer has proper SUPERSTATE_TOKEN balance"
        );

        assertEq(
            redeemerUsdcBalanceAfter,
            USDC_AMOUNT - redemptionContractUsdcBalanceAfter,
            "Redeemer has proper USDC balance"
        );
        assertEq(
            redemptionContractUsdcBalanceAfter,
            USDC_AMOUNT - redeemerUsdcBalanceAfter,
            "Contract has proper USDC balance"
        );
    }

    function testRedeemBadDataOldDataFail() public {
        vm.warp(block.timestamp + 5 days + 1);

        assertEq(USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER), 0);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), 100);
        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.redeem(100);
        vm.stopPrank();
    }

    function testRedeemAmountZeroFail() public {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.redeem(0);
    }

    function testAdminSetOracleDelay() public {
        uint256 newDelay = 1234567;

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.SetMaximumOracleDelay({oldMaxOracleDelay: MAXIMUM_ORACLE_DELAY, newMaxOracleDelay: newDelay});
        redemption.setMaximumOracleDelay(newDelay);

        assertEq(newDelay, redemption.maximumOracleDelay());
    }

    function testNonAdminSetOracleDelayFail() public {
        uint256 newDelay = 1234567;

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, SUPERSTATE_TOKEN_HOLDER));
        redemption.setMaximumOracleDelay(newDelay);
    }

    function testAdminSetOracleDelaySameFail() public {
        uint256 oldDelay = redemption.maximumOracleDelay();

        hoax(owner);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.setMaximumOracleDelay(oldDelay);
    }

    function testAdminSetSweepDestination() public {
        address newSweepDest = address(1);
        address old = redemption.sweepDestination();

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.SetSweepDestination({oldSweepDestination: old, newSweepDestination: newSweepDest});
        redemption.setSweepDestination(newSweepDest);

        assertEq(newSweepDest, redemption.sweepDestination());
    }

    function testNonAdminSetSweepDestinationFail() public {
        address newSweepDest = address(1);

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, SUPERSTATE_TOKEN_HOLDER));
        redemption.setSweepDestination(newSweepDest);
    }

    function testAdminSetSweepDestinationSameFail() public {
        address old = redemption.sweepDestination();

        hoax(owner);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.setSweepDestination(old);
    }

    function testCantRedeemPaused() public {
        hoax(owner);
        redemption.pause();

        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.redeem(1);
    }

    function testCantPauseAlreadyPaused() public {
        hoax(owner);
        redemption.pause();

        hoax(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        redemption.pause();
    }

    function testCantUnpauseAlreadyUnpaused() public {
        hoax(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        redemption.unpause();
    }

    function testCalculateUstbIn() public view {
        uint256 usdcOutAmount = 1_000_000; // 1 USDC
        (uint256 ustbInAmount, uint256 feedPrice) = redemption.calculateUstbIn(usdcOutAmount);

        // Cross check by calculating USDC out with the calculated USTB amount
        (uint256 usdcOutVerify,) = redemption.calculateUsdcOut(ustbInAmount);

        // Allow for minor rounding differences
        assertApproxEqAbs(usdcOutAmount, usdcOutVerify, 5);
        assertEq(feedPrice, 10_379_322);
    }

    function testCalculateUstbInAmountZero() public {
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.calculateUstbIn(0);
    }

    function testCalculateUstbInBadData() public {
        vm.warp(block.timestamp + 5 days + 1);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        redemption.calculateUstbIn(1_000_000);
    }

    function testCalculateUstbInFuzz(uint256 usdcOutAmount) public view {
        // Bound to reasonable values to avoid overflow
        usdcOutAmount = bound(usdcOutAmount, 1_000_000, 1e15);

        (uint256 ustbInAmount,) = redemption.calculateUstbIn(usdcOutAmount);
        (uint256 usdcOutVerify,) = redemption.calculateUsdcOut(ustbInAmount);

        // Allow for minor rounding differences due to integer division
        assertApproxEqRel(usdcOutAmount, usdcOutVerify, 1e14); // 0.01% tolerance
    }

    function testSetRedemptionFee() public {
        uint96 newFee = 5; // 0.05%

        hoax(owner);
        vm.expectEmit(true, true, true, true);
        emit IRedemption.SetRedemptionFee({oldFee: 0, newFee: newFee});
        redemption.setRedemptionFee(newFee);

        assertEq(redemption.redemptionFee(), newFee);
    }

    function testSetRedemptionFeeTooHigh() public {
        uint96 newFee = 11; // > 0.1%

        hoax(owner);
        vm.expectRevert(IRedemption.FeeTooHigh.selector);
        redemption.setRedemptionFee(newFee);
    }

    function testNonAdminSetRedemptionFeeFail() public {
        hoax(SUPERSTATE_TOKEN_HOLDER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, SUPERSTATE_TOKEN_HOLDER));
        redemption.setRedemptionFee(5);
    }

    function testSetRedemptionFeeSameFail() public {
        uint96 oldFee = redemption.redemptionFee();

        hoax(owner);
        vm.expectRevert(IRedemption.BadArgs.selector);
        redemption.setRedemptionFee(oldFee);
    }

    function testCalculateFee() public {
        uint96 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        uint256 amount = 1_000_000; // 1 USDC
        uint256 expectedFee = 500; // 0.0005 USDC

        assertEq(redemption.calculateFee(amount), expectedFee);
    }

    function testCalculateUstbInWithFee() public {
        uint96 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        uint256 usdcOutAmount = 1_000_000; // 1 USDC
        (uint256 ustbInAmount,) = redemption.calculateUstbIn(usdcOutAmount);
        (uint256 usdcOutVerify,) = redemption.calculateUsdcOut(ustbInAmount);

        // We need a larger amount of USTB to account for the fee
        assertEq(usdcOutVerify, 1_000_493);
    }

    function testRedeemWithFee() public {
        uint96 fee = 5; // 0.05%
        hoax(owner);
        redemption.setRedemptionFee(fee);

        uint256 superstateTokenAmount = redemption.maxUstbRedemptionAmount();

        vm.startPrank(SUPERSTATE_TOKEN_HOLDER);
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);
        redemption.redeem(superstateTokenAmount);
        vm.stopPrank();

        uint256 redeemerUsdcBalance = USDC.balanceOf(SUPERSTATE_TOKEN_HOLDER);
        assertEq(redeemerUsdcBalance, 9_999_999_999_996); // Original test value
    }
}
