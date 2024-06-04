// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Redemption} from "../src/Redemption.sol";

function deployRedemption(address admin, address ustb, address oracle, address usdc, uint256 maximumOracleDelay)
    returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
{
    _constructorParams = abi.encode(admin, ustb, oracle, usdc, maximumOracleDelay);
    _contractName = "";
    _address = payable(address(new Redemption(admin, ustb, oracle, usdc, maximumOracleDelay)));
}

contract DeployRedemption is Script {
    // all addresses are mainnet
    address constant ADMIN = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a;
    address constant USTB = 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e;
    address constant USTB_NAVS_ORACLE = address(0); // TODO
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // TODO: currently _maximumOracleDelay is 28 hours in seconds, confirm with chainlink their write cadence which should always be 24 hours
    uint256 constant MAXIMUM_ORACLE_DELAY = 100_800;

    address internal deployer;
    uint256 internal privateKey;

    function setUp() public {
        privateKey = vm.envUint("PK");
        deployer = vm.rememberKey(privateKey);
    }

    function run()
        public
        returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
    {
        vm.startBroadcast(deployer);
        (_address, _constructorParams, _contractName) =
            deployRedemption(ADMIN, USTB, USTB_NAVS_ORACLE, USDC, MAXIMUM_ORACLE_DELAY);

        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_address:", _address);

        vm.stopBroadcast();
    }
}
