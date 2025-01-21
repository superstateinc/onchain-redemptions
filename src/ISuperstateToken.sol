// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISuperstateToken {
    error AccountingIsNotPaused();
    error AccountingIsPaused();
    error BadArgs();
    error BadChainlinkData();
    error BadSignatory();
    error FeeTooHigh();
    error InsufficientPermissions();
    error InvalidArgumentLengths();
    error InvalidSignatureS();
    error OnchainDestinationSetForBridgeToBookEntry();
    error OnchainSubscriptionsDisabled();
    error RenounceOwnershipDisabled();
    error SafeERC20FailedOperation(address token);
    error SignatureExpired();
    error StablecoinNotSupported();
    error TwoDestinationsInvalid();
    error Unauthorized();
    error ZeroSuperstateTokensOut();

    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);
    event AdminBurn(address burner, address src, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Bridge(
        address caller,
        address src,
        uint256 amount,
        address ethDestinationAddress,
        string otherDestinationAddress,
        uint256 chainId
    );
    event Initialized(uint8 version);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event OffchainRedeem(address burner, address src, uint256 amount);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event SetMaximumOracleDelay(uint256 oldMaxOracleDelay, uint256 newMaxOracleDelay);
    event SetOracle(address oldOracle, address newOracle);
    event SetRedemptionContract(address oldRedemptionContract, address newRedemptionContract);
    event SetStablecoinConfig(
        address indexed stablecoin,
        address oldSweepDestination,
        address newSweepDestination,
        uint96 oldFee,
        uint96 newFee
    );
    event Subscribe(
        address indexed subscriber,
        address stablecoin,
        uint256 stablecoinInAmount,
        uint256 stablecoinInAmountAfterFee,
        uint256 superstateTokenOutAmount
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unpaused(address account);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function FEE_DENOMINATOR() external view returns (uint256);
    function MINIMUM_ACCEPTABLE_PRICE() external view returns (uint256);
    function SUPERSTATE_TOKEN_PRECISION() external view returns (uint256);
    function VERSION() external view returns (string memory);
    function _deprecatedAdmin() external view returns (address);
    function _deprecatedAllowList() external view returns (address);
    function _deprecatedEncumberedBalanceOf(address) external view returns (uint256);
    function _deprecatedEncumbrances(address, address) external view returns (uint256);
    function acceptOwnership() external;
    function accountingPause() external;
    function accountingPaused() external view returns (bool);
    function accountingUnpause() external;
    function adminBurn(address src, uint256 amount) external;
    function allowListV2() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function bridge(
        uint256 amount,
        address ethDestinationAddress,
        string memory otherDestinationAddress,
        uint256 chainId
    ) external;
    function bridgeToBookEntry(uint256 amount) external;
    function bulkMint(address[] memory dsts, uint256[] memory amounts) external;
    function calculateFee(uint256 amount, uint256 subscriptionFee) external pure returns (uint256);
    function calculateSuperstateTokenOut(uint256 inAmount, address stablecoin)
    external
    view
    returns (uint256 superstateTokenOutAmount, uint256 stablecoinInAmountAfterFee, uint256 feeOnStablecoinInAmount);
    function decimals() external pure returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function getChainlinkPrice() external view returns (bool _isBadData, uint256 _updatedAt, uint256 _price);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(string memory _name, string memory _symbol) external;
    function initializeV2() external;
    function initializeV3(address _allowList) external;
    function isAllowed(address addr) external view returns (bool);
    function maximumOracleDelay() external view returns (uint256);
    function mint(address dst, uint256 amount) external;
    function name() external view returns (string memory);
    function nonces(address) external view returns (uint256);
    function offchainRedeem(uint256 amount) external;
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function pendingOwner() external view returns (address);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external;
    function redemptionContract() external view returns (address);
    function renounceOwnership() external;
    function setMaximumOracleDelay(uint256 _newMaxOracleDelay) external;
    function setOracle(address _newOracle) external;
    function setRedemptionContract(address _newRedemptionContract) external;
    function setStablecoinConfig(address stablecoin, address newSweepDestination, uint96 newFee) external;
    function subscribe(uint256 inAmount, address stablecoin) external;
    function superstateOracle() external view returns (address);
    function supportedStablecoins(address stablecoin) external view returns (address sweepDestination, uint96 fee);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
    function unpause() external;
}