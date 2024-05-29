// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract Redemption {
    address public immutable USTB;
    AggregatorV3Interface public immutable USTB_ORACLE;
    address public immutable USDC;

    constructor(address fraxGovernorOmega) {
        = fraxGovernorOmega;
    }

}
