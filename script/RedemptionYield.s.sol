// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RedemptionYield} from "../src/RedemptionYield.sol";
import {IRedemption} from "src/interfaces/IRedemption.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

function deployRedemptionYield(
    address ustb,
    address oracle,
    address usdc,
    address proxyOwner,
    address redemptionOwner,
    uint256 maximumOracleDelay,
    address compound
)
    returns (
        address payable _implementation,
        bytes memory _constructorParams,
        string memory _contractName,
        address _proxy
    )
{
    _constructorParams = abi.encode(ustb, oracle, usdc);
    _contractName = "";
    _implementation = payable(address(new RedemptionYield(ustb, oracle, usdc, compound)));

    TransparentUpgradeableProxy redemptionProxy =
        new TransparentUpgradeableProxy(address(_implementation), proxyOwner, "");

    _proxy = address(redemptionProxy);

    IRedemption(_proxy).initialize(redemptionOwner, maximumOracleDelay);
}

contract DeployRedemptionYield is Script {
    // all addresses are mainnet
    address constant PROXY_OWNER = address(0); // TODO
    address constant REDEMPTION_OWNER = address(0); // TODO
    address constant USTB = 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e;
    address constant USTB_NAVS_ORACLE = address(0); // TODO
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant COMPOUND = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;

    uint256 constant MAXIMUM_ORACLE_DELAY = 93_600;

    address internal deployer;
    uint256 internal privateKey;

    function setUp() public {
        privateKey = vm.envUint("PK");
        deployer = vm.rememberKey(privateKey);
    }

    function run()
        public
        returns (address payable _address, bytes memory _constructorParams, string memory _contractName, address _proxy)
    {
        vm.startBroadcast(deployer);
        (_address, _constructorParams, _contractName, _proxy) = deployRedemptionYield(
            USTB, USTB_NAVS_ORACLE, USDC, PROXY_OWNER, REDEMPTION_OWNER, MAXIMUM_ORACLE_DELAY, COMPOUND
        );

        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_address:", _address);
        console.log("_proxy:", _proxy);

        vm.stopBroadcast();
    }
}
