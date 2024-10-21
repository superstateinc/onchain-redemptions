// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SuperstateOracle} from "../src/oracle/SuperstateOracle.sol";

function deploySuperstateOracle(address initialOwner, address ustb)
    returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
{
    _constructorParams = abi.encode(initialOwner, ustb);
    _contractName = "";
    _address = payable(address(new SuperstateOracle(initialOwner, ustb)));
}

contract DeploySuperstateOracle is Script {
    // all addresses are mainnet
    address public constant ADMIN = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a; // TODO: update
    address public constant USTB = 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e;

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
        (_address, _constructorParams, _contractName) = deploySuperstateOracle(ADMIN, USTB);

        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_address:", _address);

        vm.stopBroadcast();
    }
}
