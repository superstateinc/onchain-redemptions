// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {RedemptionIdleTestV1} from "test/v1/RedemptionIdleV1.t.sol";
import {RedemptionIdleV2} from "src/v2/RedemptionIdleV2.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";
import {ISuperstateToken} from "src/ISuperstateToken.sol";
import {Redemption} from "src/Redemption.sol";
import {RedemptionIdle} from "src/RedemptionIdle.sol";
import {IRedemptionIdle} from "src/interfaces/IRedemptionIdle.sol";
import {deployRedemptionIdleV1} from "script/RedemptionIdle.s.sol";
import {SuperstateOracle} from "src/oracle/SuperstateOracle.sol";
import {deploySuperstateOracle} from "script/SuperstateOracle.s.sol";
import {AllowList} from "ustb/src/allowlist/AllowList.sol";
import {IAllowListV2} from "ustb/src/interfaces/allowlist/IAllowListV2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract RedemptionIdleTestV2 is RedemptionIdleTestV1 {
    RedemptionIdle public redemptionV2;
    AllowList public constant allowListV2 = AllowList(0x02f1fA8B196d21c7b733EB2700B825611d8A38E5);
    IAllowListV2.EntityId ENTITY_ID_V2 = IAllowListV2.EntityId.wrap(1);
    address public allowListV2Admin = 0x7747940aDBc7191f877a9B90596E0DA4f8deb2Fe;

    uint256 public forkBlockNumberV2 = 21_933_146;
    uint256 public rollBlockNumberV2 = 21_993_400;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), forkBlockNumberV2);
        vm.roll(rollBlockNumberV2);
        vm.warp(1726779601);

        (address payable _addressOracle,,) = deploySuperstateOracle(owner, address(SUPERSTATE_TOKEN), 1_000_000);
        oracle = SuperstateOracle(_addressOracle);

        hoax(owner);
        oracle.addCheckpoint(1726779600, 1726779601, 10_374_862, false);

        vm.warp(1726866001);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_379_322, false);

        (,,, address proxy) = deployRedemptionIdleV1(
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
        redemptionProxy = ITransparentUpgradeableProxy(payable(proxy));
        redemptionProxyAdmin = ProxyAdmin(getAdminAddress(address(redemptionProxy)));

        // 10 million
        deal(address(USDC), SUPERSTATE_TOKEN_HOLDER, USDC_AMOUNT);
        deal(address(SUPERSTATE_TOKEN), SUPERSTATE_TOKEN_HOLDER, USDC_AMOUNT);

        hoax(SUPERSTATE_TOKEN_HOLDER);
        USDC.transfer(address(redemption), USDC_AMOUNT);

        assertGe(USDC.balanceOf(address(redemption)), 0);

        vm.startPrank(allowListV2Admin);
        allowListV2.setEntityIdForAddress(ENTITY_ID_V2, address(redemption));
        vm.stopPrank();

        redemptionV2 = new RedemptionIdle(address(SUPERSTATE_TOKEN), address(oracle), address(USDC));
        redemptionProxyAdmin.upgradeAndCall(redemptionProxy, address(redemptionV2), "");
        redemption = IRedemptionIdle(address(redemptionProxy));
    }

    function testRedeem() public virtual override {
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
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval({
            owner: SUPERSTATE_TOKEN_HOLDER,
            spender: address(redemption),
            value: superstateTokenAmount
        });
        SUPERSTATE_TOKEN.approve(address(redemption), superstateTokenAmount);

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Transfer({
            from: SUPERSTATE_TOKEN_HOLDER,
            to: address(redemption),
            value: superstateTokenAmount
        });

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer({from: address(redemption), to: SUPERSTATE_TOKEN_HOLDER, value: 9999999999996});

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.Transfer({from: address(redemption), to: address(0), value: superstateTokenAmount});

        vm.expectEmit(true, true, true, true);
        emit ISuperstateToken.OffchainRedeem({
            burner: address(redemptionProxy),
            src: address(redemptionProxy),
            amount: superstateTokenAmount
        });

        vm.expectEmit(true, true, true, true);
        emit IRedemption.RedeemV3({
            redeemer: SUPERSTATE_TOKEN_HOLDER,
            to: SUPERSTATE_TOKEN_HOLDER,
            superstateTokenInAmount: superstateTokenAmount,
            usdcOutAmount: 9999999999996,
            usdcOutAmountWithFee: 9999999999996
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
