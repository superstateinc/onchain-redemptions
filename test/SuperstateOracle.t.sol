// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SuperstateOracle} from "../src/oracle/SuperstateOracle.sol";
import {deploySuperstateOracle} from "../script/SuperstateOracle.s.sol";

contract SuperstateOracleTest is Test {
    address public owner = address(this);
    IERC20 public constant USTB = IERC20(0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);

    SuperstateOracle public oracle;

    address public alice = address(10);
    address public bob = address(11);

    function setUp() public {
        vm.warp(1_729_266_022);
        vm.roll(20_993_400);

        (address payable _address,,) = deploySuperstateOracle(owner, address(USTB));

        oracle = SuperstateOracle(_address);
    }

    function testDecimals() public view {
        assertEq(oracle.decimals(), 6);
    }

    function testVersion() public view {
        assertEq(oracle.version(), 1);
    }

    function testDescription() public view {
        assertEq(oracle.description(), "Realtime USTB Net Asset Value per Share (NAV/S) Oracle");
    }

    function testUstbTokenProxyAddress() public view {
        assertEq(oracle.USTB_TOKEN_PROXY_ADDRESS(), 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e);
    }

    function testGetRoundDataNotImplemented() public {
        vm.expectRevert(SuperstateOracle.NotImplemented.selector);
        oracle.getRoundData(0);
    }

    function testOwner() public view {
        assertEq(oracle.owner(), owner);
    }

    function testAddCheckpointWrongOwner() public {
        hoax(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        oracle.addCheckpoint(0, 0, 0, false);
    }

    function testAddCheckpointsWrongOwner() public {
        // Create an array with one NavsCheckpoint, all fields initialized to 0
        SuperstateOracle.NavsCheckpoint[] memory checkpoints = new SuperstateOracle.NavsCheckpoint[](1);

        hoax(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        oracle.addCheckpoints(checkpoints);
    }

    function testAddCheckpointTimestampInvalid() public {
        hoax(owner);
        vm.expectRevert(SuperstateOracle.TimestampInvalid.selector);
        oracle.addCheckpoint(uint64(block.timestamp), uint64(block.timestamp + 100), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.TimestampInvalid.selector);
        oracle.addCheckpoint(uint64(block.timestamp + 1), uint64(block.timestamp + 100), 10_000_000, false);
    }

    function testAddCheckpointEffectiveAtInvalid() public {
        hoax(owner);
        vm.expectRevert(SuperstateOracle.EffectiveAtInvalid.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp - 1), 10_000_000, false);
    }

    function testAddCheckpointNetAssetValuePerShareInvalid() public {
        hoax(owner);
        vm.expectRevert(SuperstateOracle.NetAssetValuePerShareInvalid.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 100), 6_999_999, false);
    }

    function testAddCheckpointTimestampNotChronological() public {
        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 100), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.TimestampNotChronological.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 200), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.TimestampNotChronological.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 101), uint64(block.timestamp + 200), 10_000_000, false);
    }

    function testAddCheckpointEffectiveAtNotChronological() public {
        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 100), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.EffectiveAtNotChronological.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 99), uint64(block.timestamp + 100), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.EffectiveAtNotChronological.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 99), uint64(block.timestamp + 99), 10_000_000, false);
    }

    function testAddCheckpointExistingPendingEffectiveAt() public {
        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 100), 10_000_000, false);

        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 50), uint64(block.timestamp + 150), 10_000_000, false);

        hoax(owner);
        vm.expectRevert(SuperstateOracle.ExistingPendingEffectiveAt.selector);
        oracle.addCheckpoint(uint64(block.timestamp - 49), uint64(block.timestamp + 151), 10_000_000, false);

        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 49), uint64(block.timestamp + 151), 10_000_000, true);
    }

    function testLatestRoundDataCantGeneratePriceNotEnoughCheckpoints() public {
        vm.expectRevert(SuperstateOracle.CantGeneratePrice.selector); // no checkpoints
        oracle.latestRoundData();

        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), uint64(block.timestamp + 100), 10_000_000, false);

        vm.expectRevert(SuperstateOracle.CantGeneratePrice.selector); // only one checkpoint
        oracle.latestRoundData();
    }

    function testLatestRoundDataNotEnoughEffectiveCheckpoints() public {
        uint64 effectiveAtBlock = uint64(block.timestamp + 100);

        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), effectiveAtBlock, 10_000_000, false);

        vm.warp(effectiveAtBlock);

        hoax(owner);
        oracle.addCheckpoint(uint64(block.timestamp - 100), effectiveAtBlock + 100, 10_000_000, false);

        vm.expectRevert(SuperstateOracle.CantGeneratePrice.selector); // only one effective checkpoint
        oracle.latestRoundData();

        vm.warp(effectiveAtBlock + 100);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(10_000_000, answer);
    }

    function testLatestRoundDataRealData() public {
        vm.warp(1726779601);

        hoax(owner);
        oracle.addCheckpoint(1726779600, 1726779601, 10_374_862, false);

        vm.warp(1726866001);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_379_322, false);

        vm.warp(1726920000);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(10_382_109, answer);

        vm.warp(1726866001 + oracle.CHECKPOINT_EXPIRATION_PERIOD() + 1);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        oracle.latestRoundData();
    }

    function testLatestRoundDataRealDataDecreasing() public {
        vm.warp(1726779601);

        hoax(owner);
        oracle.addCheckpoint(1726779600, 1726779601, 10_379_322, false);  // Swapped: was 10_374_862

        vm.warp(1726866001);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_374_862, false);  // Swapped: was 10_379_322

        vm.warp(1726920000);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(10_372_075, answer);  // New expected value for decreasing case

        vm.warp(1726866001 + oracle.CHECKPOINT_EXPIRATION_PERIOD() + 1);

        vm.expectRevert(SuperstateOracle.StaleCheckpoint.selector);
        oracle.latestRoundData();
    }

    function testAddCheckpoints() public {
        SuperstateOracle.NavsCheckpoint[] memory checkpoints = new SuperstateOracle.NavsCheckpoint[](2);

        checkpoints[0] = SuperstateOracle.NavsCheckpoint({
            timestamp: uint64(block.timestamp - 100),
            effectiveAt: uint64(block.timestamp + 1 hours),
            navs: 10_000_000
        });

        checkpoints[1] = SuperstateOracle.NavsCheckpoint({
            timestamp: uint64(block.timestamp - 50),
            effectiveAt: uint64(block.timestamp + 1 days),
            navs: 11_000_000
        });

        hoax(owner);
        oracle.addCheckpoints(checkpoints);
    }

    function testLatestRoundDataEffectiveAtThirdCheckpoint() public {
        vm.warp(1726779601);

        hoax(owner);
        oracle.addCheckpoint(1726779600, 1726779601, 10_374_862, false);

        vm.warp(1726866001);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726866000), 1726866001, 10_379_322, false);

        vm.warp(1726920000);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(10_382_109, answer);

        hoax(owner);
        oracle.addCheckpoint(uint64(1726920000 - 1), 1726920000 + 1, 500_000_000, false);

        (, int256 answer2,,,) = oracle.latestRoundData();
        assertEq(10_382_109, answer2);

        vm.warp(1726920000 + 1); // price changes now since new crazy high checkpoint is now effective_at

        (, int256 answer3,,,) = oracle.latestRoundData();
        assertEq(500_018_134, answer3);
    }
}
