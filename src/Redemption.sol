// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Redemption {
    using SafeERC20 for IERC20;

    address public immutable USTB;
    AggregatorV3Interface public immutable USTB_ORACLE;
    IERC20 public immutable USDC;

    /// @notice Admin address with exclusive privileges for withdrawing tokens
    address public immutable ADMIN;

    /// @dev TODO
    error BadArgs();

    /// @dev Thrown when a request is not sent by the authorized admin
    error Unauthorized();

    /// @dev TODO
    error InsufficientBalance();

    constructor(address _admin, address _ustb, address _ustbOracle, address _usdc) {
        ADMIN = _admin;
        USTB = _ustb;
        USTB_ORACLE = AggregatorV3Interface(_ustbOracle);
        USDC = IERC20(_usdc);
    }

    function _requireAuthorized() internal view {
//        require(msg.sender != ADMIN, Unauthorized());
    }

    // user approves usdc in our ui, outside of this contract
    // user calls redeem function
    // redeem function takes ustb amount as arg, spends allowance of ustb, calcs usdc out amount, burns ustb
    function redeem(uint256 amount) external {
        (, int256 answer, uint256 startedAt, uint256 updatedAt,) =
            USTB_ORACLE.latestRoundData();
    }

    // transfer in usdc, outside of this contract
    function withdraw(address _token, address to, uint256 amount) external {
        _requireAuthorized();
//        require(amount > 0, BadArgs());

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));

//        require(balance >= amount, InsufficientBalance());

        token.safeTransfer(to, amount);
    }
}
