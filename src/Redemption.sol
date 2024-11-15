// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISuperstateToken} from "./ISuperstateToken.sol";
import {IRedemption} from "./interfaces/IRedemption.sol";

/// @title Redemption
/// @author Jon Walch and Max Wolff (Superstate)
/// @notice Abstract contract that provides base functionality for Superstate Token redemption
abstract contract Redemption is PausableUpgradeable, Ownable2StepUpgradeable, IRedemption {
    /**
     * @dev This empty reserved space is put in place to allow future versions to inherit from new contracts
     * without impacting the fields within `Redemption`.
     */
    uint256[500] private __inheritanceGap;

    /// @notice Decimals of USDC
    uint256 public constant USDC_DECIMALS = 6;

    /// @notice Precision of USDC
    uint256 public constant USDC_PRECISION = 10 ** USDC_DECIMALS;

    /// @notice Decimals of SUPERSTATE_TOKEN
    uint256 public constant SUPERSTATE_TOKEN_DECIMALS = 6;

    /// @notice Precision of SUPERSTATE_TOKEN
    uint256 public constant SUPERSTATE_TOKEN_PRECISION = 10 ** SUPERSTATE_TOKEN_DECIMALS;

    /// @notice Base 10000 for 0.01% precision
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @notice Chainlink aggregator
    address public immutable CHAINLINK_FEED_ADDRESS;

    /// @notice Decimals of SUPERSTATE_TOKEN/USD chainlink feed
    uint8 public immutable CHAINLINK_FEED_DECIMALS;

    /// @notice Precision of SUPERSTATE_TOKEN/USD chainlink feed
    uint256 public immutable CHAINLINK_FEED_PRECISION;

    /// @notice Lowest acceptable chainlink oracle price
    uint256 public immutable MINIMUM_ACCEPTABLE_PRICE;

    /// @notice The SUPERSTATE_TOKEN contract
    IERC20 public immutable SUPERSTATE_TOKEN;

    /// @notice The USDC contract
    IERC20 public immutable USDC;

    /// @notice Value, in seconds, that determines if chainlink data is too old
    uint256 public maximumOracleDelay;

    /// @notice Default where USDC gets swept to
    address public sweepDestination;

    // @notice A fee charged on incoming USDC
    uint256 public redemptionFee;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new fields without impacting
     * any contracts that inherit `Redemption`
     */
    uint256[100] private __additionalFieldsGap;

    constructor(address _superstateToken, address _superstateTokenChainlinkFeedAddress, address _usdc) {
        CHAINLINK_FEED_ADDRESS = _superstateTokenChainlinkFeedAddress;
        CHAINLINK_FEED_DECIMALS = AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).decimals();
        CHAINLINK_FEED_PRECISION = 10 ** uint256(CHAINLINK_FEED_DECIMALS);
        MINIMUM_ACCEPTABLE_PRICE = 7 * (10 ** uint256(CHAINLINK_FEED_DECIMALS));

        SUPERSTATE_TOKEN = IERC20(_superstateToken);
        USDC = IERC20(_usdc);

        require(ERC20(_superstateToken).decimals() == SUPERSTATE_TOKEN_DECIMALS);
        require(ERC20(_usdc).decimals() == USDC_DECIMALS);

        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        uint256 _maximumOracleDelay,
        address _sweepDestination,
        uint256 _redemptionFee
    ) external initializer {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();

        _setMaximumOracleDelay(_maximumOracleDelay);
        _setSweepDestination(_sweepDestination);

        redemptionFee = _redemptionFee;
        emit SetRedemptionFee({oldFee: 0, newFee: _redemptionFee});
    }

    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }

    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * redemptionFee) / FEE_DENOMINATOR;
    }

    function _setRedemptionFee(uint256 _newFee) internal {
        if (_newFee > 10) revert FeeTooHigh(); // Max 0.1% fee
        if (redemptionFee == _newFee) revert BadArgs();
        emit SetRedemptionFee({oldFee: redemptionFee, newFee: _newFee});
        redemptionFee = _newFee;
    }

    /// @notice Sets redemption fee percentage (in basis points)
    /// @dev Only callable by the admin
    /// @dev Fee cannot exceed 10 basis points (0.1%)
    /// @param _newFee New fee in basis points. 1 = 0.01%, 5 = 0.05%, 10 = 0.1%
    function setRedemptionFee(uint256 _newFee) external {
        _checkOwner();
        _setRedemptionFee(_newFee);
    }

    /// @notice Invokes the {Pausable-_pause} internal function
    function pause() external {
        _checkOwner();
        _requireNotPaused();
        _pause();
    }

    /// @notice Invokes the {Pausable-_unpause} internal function
    function unpause() external {
        _checkOwner();
        _requirePaused();
        _unpause();
    }

    function _setSweepDestination(address _newSweepDestination) internal {
        if (sweepDestination == _newSweepDestination) revert BadArgs();
        emit SetSweepDestination({oldSweepDestination: sweepDestination, newSweepDestination: _newSweepDestination});
        sweepDestination = _newSweepDestination;
    }

    /// @notice Sets the sweep destination for withdrawToSweepDestination
    function setSweepDestination(address _newSweepDestination) external {
        _checkOwner();
        _setSweepDestination(_newSweepDestination);
    }

    function _setMaximumOracleDelay(uint256 _newMaxOracleDelay) internal {
        if (maximumOracleDelay == _newMaxOracleDelay) revert BadArgs();
        emit SetMaximumOracleDelay({oldMaxOracleDelay: maximumOracleDelay, newMaxOracleDelay: _newMaxOracleDelay});
        maximumOracleDelay = _newMaxOracleDelay;
    }

    /// @notice Sets the max oracle delay to determine if Chainlink data is stale
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external {
        _checkOwner();
        _setMaximumOracleDelay(_newMaxOracleDelay);
    }

    function _getChainlinkPrice() internal view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) =
            AggregatorV3Interface(CHAINLINK_FEED_ADDRESS).latestRoundData();

        _isBadData =
            _answer < int256(MINIMUM_ACCEPTABLE_PRICE) || ((block.timestamp - _chainlinkUpdatedAt) > maximumOracleDelay);
        _updatedAt = _chainlinkUpdatedAt;
        _price = uint256(_answer);
    }

    /// @notice Returns the chainlink price and the timestamp of the last update
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price) {
        return _getChainlinkPrice();
    }

    /**
     * @notice The ```calculateUstbIn``` function calculates how many Superstate tokens you need to redeem to receive a specific USDC amount
     * @param usdcOutAmount The desired amount of USDC to receive
     * @return ustbInAmount The amount of Superstate tokens needed
     * @return usdPerUstbChainlinkRaw The raw chainlink price used in calculation
     */
    function calculateUstbIn(uint256 usdcOutAmount)
        public
        view
        returns (uint256 ustbInAmount, uint256 usdPerUstbChainlinkRaw)
    {
        if (usdcOutAmount == 0) revert BadArgs();

        uint256 usdcOutAmountWithFee = usdcOutAmount + calculateFee(usdcOutAmount);

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw_) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        usdPerUstbChainlinkRaw = usdPerUstbChainlinkRaw_;

        ustbInAmount = (usdcOutAmountWithFee * CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION)
            / (usdPerUstbChainlinkRaw * USDC_PRECISION);
    }

    /**
     * @notice The ```calculateUsdcOut``` function calculates the total amount of USDC you'll receive for redeeming Superstate tokens
     * @param superstateTokenInAmount The amount of Superstate tokens to redeem
     * @return usdcOutAmount The amount of USDC received for redeeming superstateTokenInAmount
     * @return usdPerUstbChainlinkRaw The raw chainlink price used in calculation
     */
    function calculateUsdcOut(uint256 superstateTokenInAmount)
        public
        view
        returns (uint256 usdcOutAmount, uint256 usdPerUstbChainlinkRaw)
    {
        if (superstateTokenInAmount == 0) revert BadArgs();

        (bool isBadData,, uint256 usdPerUstbChainlinkRaw_) = _getChainlinkPrice();
        if (isBadData) revert BadChainlinkData();

        usdPerUstbChainlinkRaw = usdPerUstbChainlinkRaw_;

        uint256 rawUsdcAmount = (superstateTokenInAmount * usdPerUstbChainlinkRaw * USDC_PRECISION)
            / (CHAINLINK_FEED_PRECISION * SUPERSTATE_TOKEN_PRECISION);

        uint256 fee = calculateFee(rawUsdcAmount);
        usdcOutAmount = rawUsdcAmount - fee;
    }

    /// @notice Abstract function that must be implemented by derived contracts
    /// @return _superstateTokenAmount The maximum amount of SUPERSTATE_TOKEN that can be redeemed
    function maxUstbRedemptionAmount() external view virtual returns (uint256 _superstateTokenAmount);

    /// @notice Abstract function that must be implemented by derived contracts
    /// @param superstateTokenInAmount The amount of SUPERSTATE_TOKEN to redeem
    function redeem(uint256 superstateTokenInAmount) external virtual;

    /// @notice Abstract function that must be implemented by derived contracts
    /// @param _token The address of the token to withdraw
    /// @param to The address where the tokens are going
    /// @param amount The amount of token to withdraw
    function withdraw(address _token, address to, uint256 amount) public virtual;

    /// @notice The ```withdrawToSweepDestination``` function calls ```withdraw``` with added safety rails
    /// @param amount The amount of token to withdraw
    function withdrawToSweepDestination(uint256 amount) external {
        withdraw({_token: address(USDC), to: sweepDestination, amount: amount});
    }
}
