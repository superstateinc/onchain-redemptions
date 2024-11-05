// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IRedemption {
    /// @notice The ```SetMaximumOracleDelay``` event is emitted when the max oracle delay is set
    /// @param oldMaxOracleDelay The old max oracle delay
    /// @param newMaxOracleDelay The new max oracle delay
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);

    /// @dev Event emitted when SUPERSTATE_TOKEN is redeemed for USDC
    /// @param redeemer The address of the entity redeeming
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    /// @param usdcOutAmount The amount of USDC the redeemer gets back
    event Redeem(address indexed redeemer, uint256 superstateTokenInAmount, uint256 usdcOutAmount);

    /// @dev Event emitted when tokens are withdrawn
    /// @param token The address of the token being withdrawn
    /// @param withdrawer The address of the caller
    /// @param to The address receiving the tokens
    /// @param amount The amount of token the redeemer gets back
    event Withdraw(address indexed token, address indexed withdrawer, address indexed to, uint256 amount);

    /// @dev Thrown when an argument is invalid
    error BadArgs();

    /// @dev Thrown when Chainlink Oracle data is bad
    error BadChainlinkData();

    /// @dev Thrown when there isn't enough token balance in the contract
    error InsufficientBalance();

    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price);
    function maxUstbRedemptionAmount() external view returns (uint256 _superstateTokenAmount);
    function maximumOracleDelay() external view returns (uint256);
    function pause() external;
    function redeem(uint256 superstateTokenInAmount) external;
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external;
    function unpause() external;
    function withdraw(address _token, address to, uint256 amount) external;
    function initialize(address initialOwner, uint256 maximumOracleDelay) external;
}
