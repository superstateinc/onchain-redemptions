// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRedemptionV2} from "./IRedemptionV2.sol";

interface IRedemptionYieldV2 is IRedemptionV2 {
    /// @dev Event emitted when usdc is deposited into the contract via the deposit function
    event Deposit(address indexed token, address indexed depositor, uint256 amount);

    function deposit(uint256 usdcAmount) external;
}
