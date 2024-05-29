// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Redemption {
    address public immutable USTB;
    AggregatorV3Interface public immutable USTB_ORACLE;
    address public immutable USDC;

    /// @notice Admin address with exclusive privileges for withdrawing tokens
    address public immutable ADMIN;

    constructor(address _ustb, address _ustbOracle, address _usdc) {
        USTB = _ustb;
        USTB_ORACLE = AggregatorV3Interface(_ustbOracle);
        USDC = _usdc;
    }

    // transfer in usdc
    // function to withdraw usdc

}
