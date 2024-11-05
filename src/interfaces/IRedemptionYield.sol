// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRedemption} from "./IRedemption.sol";

interface IRedemptionYield is IRedemption{
    /// @dev Event emitted when usdc is deposited into the contract via the deposit function
    event Deposit(address indexed token, address indexed depositor, uint256 amount);

    function deposit(uint256 usdcAmount) external;
}
