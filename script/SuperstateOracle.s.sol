// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SuperstateOracle} from "../src/oracle/SuperstateOracle.sol";

function deploySuperstateOracle(address initialOwner, address ustb, uint256 maximumAcceptablePriceDelta)
    returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
{
    _constructorParams = abi.encode(initialOwner, ustb);
    _contractName = "";
    _address = payable(address(new SuperstateOracle(initialOwner, ustb, maximumAcceptablePriceDelta)));
}

contract DeploySuperstateOracle is Script {
    // all addresses are sepolia
    address public constant ADMIN = 0x8C7Db8A96d39F76D9f456db23d591C2FDd0e2F8a; //TODO
    address public constant USTB = 0x03891c84c877d68DA8d3E4189b74c3e44a1C2B63;
    uint256 public constant MAXIMUM_ACCEPTABLE_PRICE_DELTA = 1_000_000;

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
            deploySuperstateOracle(ADMIN, USTB, MAXIMUM_ACCEPTABLE_PRICE_DELTA);

        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_address:", _address);

        vm.stopBroadcast();
    }
}
