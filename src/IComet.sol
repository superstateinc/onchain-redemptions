// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IComet {
    struct AssetInfo {
        uint8 offset;
        address asset;
        address priceFeed;
        uint64 scale;
        uint64 borrowCollateralFactor;
        uint64 liquidateCollateralFactor;
        uint64 liquidationFactor;
        uint128 supplyCap;
    }

    error Absurd();
    error AlreadyInitialized();
    error BadAsset();
    error BadDecimals();
    error BadDiscount();
    error BadMinimum();
    error BadPrice();
    error BorrowCFTooLarge();
    error BorrowTooSmall();
    error InsufficientReserves();
    error InvalidInt104();
    error InvalidInt256();
    error InvalidUInt104();
    error InvalidUInt128();
    error InvalidUInt64();
    error LiquidateCFTooLarge();
    error NegativeNumber();
    error NoSelfTransfer();
    error NotCollateralized();
    error NotForSale();
    error NotLiquidatable();
    error Paused();
    error SupplyCapExceeded();
    error TimestampTooLarge();
    error TooManyAssets();
    error TooMuchSlippage();
    error TransferInFailed();
    error TransferOutFailed();
    error Unauthorized();

    event AbsorbCollateral(
        address indexed absorber,
        address indexed borrower,
        address indexed asset,
        uint256 collateralAbsorbed,
        uint256 usdValue
    );
    event AbsorbDebt(address indexed absorber, address indexed borrower, uint256 basePaidOut, uint256 usdValue);
    event BuyCollateral(address indexed buyer, address indexed asset, uint256 baseAmount, uint256 collateralAmount);
    event PauseAction(bool supplyPaused, bool transferPaused, bool withdrawPaused, bool absorbPaused, bool buyPaused);
    event Supply(address indexed from, address indexed dst, uint256 amount);
    event SupplyCollateral(address indexed from, address indexed dst, address indexed asset, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TransferCollateral(address indexed from, address indexed to, address indexed asset, uint256 amount);
    event Withdraw(address indexed src, address indexed to, uint256 amount);
    event WithdrawCollateral(address indexed src, address indexed to, address indexed asset, uint256 amount);
    event WithdrawReserves(address indexed to, uint256 amount);

    function absorb(address absorber, address[] memory accounts) external;
    function accrueAccount(address account) external;
    function approveThis(address manager, address asset, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function baseBorrowMin() external view returns (uint256);
    function baseMinForRewards() external view returns (uint256);
    function baseScale() external view returns (uint256);
    function baseToken() external view returns (address);
    function baseTokenPriceFeed() external view returns (address);
    function baseTrackingBorrowSpeed() external view returns (uint256);
    function baseTrackingSupplySpeed() external view returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);
    function borrowKink() external view returns (uint256);
    function borrowPerSecondInterestRateBase() external view returns (uint256);
    function borrowPerSecondInterestRateSlopeHigh() external view returns (uint256);
    function borrowPerSecondInterestRateSlopeLow() external view returns (uint256);
    function buyCollateral(address asset, uint256 minAmount, uint256 baseAmount, address recipient) external;
    function decimals() external view returns (uint8);
    function extensionDelegate() external view returns (address);
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);
    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);
    function getBorrowRate(uint256 utilization) external view returns (uint64);
    function getCollateralReserves(address asset) external view returns (uint256);
    function getPrice(address priceFeed) external view returns (uint256);
    function getReserves() external view returns (int256);
    function getSupplyRate(uint256 utilization) external view returns (uint64);
    function getUtilization() external view returns (uint256);
    function governor() external view returns (address);
    function hasPermission(address owner, address manager) external view returns (bool);
    function initializeStorage() external;
    function isAbsorbPaused() external view returns (bool);
    function isAllowed(address, address) external view returns (bool);
    function isBorrowCollateralized(address account) external view returns (bool);
    function isBuyPaused() external view returns (bool);
    function isLiquidatable(address account) external view returns (bool);
    function isSupplyPaused() external view returns (bool);
    function isTransferPaused() external view returns (bool);
    function isWithdrawPaused() external view returns (bool);
    function liquidatorPoints(address)
        external
        view
        returns (uint32 numAbsorbs, uint64 numAbsorbed, uint128 approxSpend, uint32 _reserved);
    function numAssets() external view returns (uint8);
    function pause(bool supplyPaused, bool transferPaused, bool withdrawPaused, bool absorbPaused, bool buyPaused)
        external;
    function pauseGuardian() external view returns (address);
    function quoteCollateral(address asset, uint256 baseAmount) external view returns (uint256);
    function storeFrontPriceFactor() external view returns (uint256);
    function supply(address asset, uint256 amount) external;
    function supplyFrom(address from, address dst, address asset, uint256 amount) external;
    function supplyKink() external view returns (uint256);
    function supplyPerSecondInterestRateBase() external view returns (uint256);
    function supplyPerSecondInterestRateSlopeHigh() external view returns (uint256);
    function supplyPerSecondInterestRateSlopeLow() external view returns (uint256);
    function supplyTo(address dst, address asset, uint256 amount) external;
    function targetReserves() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalsCollateral(address) external view returns (uint128 totalSupplyAsset, uint128 _reserved);
    function trackingIndexScale() external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferAsset(address dst, address asset, uint256 amount) external;
    function transferAssetFrom(address src, address dst, address asset, uint256 amount) external;
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function userBasic(address)
        external
        view
        returns (
            int104 principal,
            uint64 baseTrackingIndex,
            uint64 baseTrackingAccrued,
            uint16 assetsIn,
            uint8 _reserved
        );
    function userCollateral(address, address) external view returns (uint128 balance, uint128 _reserved);
    function userNonce(address) external view returns (uint256);
    function withdraw(address asset, uint256 amount) external;
    function withdrawFrom(address src, address to, address asset, uint256 amount) external;
    function withdrawReserves(address to, uint256 amount) external;
    function withdrawTo(address to, address asset, uint256 amount) external;
}
