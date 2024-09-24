// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface ISuperstateToken {
    error AccountingIsNotPaused();
    error AccountingIsPaused();
    error BadSignatory();
    error InsufficientAvailableBalance();
    error InsufficientEncumbrance();
    error InsufficientPermissions();
    error InvalidArgumentLengths();
    error InvalidSignatureS();
    error SelfEncumberNotAllowed();
    error SignatureExpired();
    error Unauthorized();

    event AccountingPaused(address admin);
    event AccountingUnpaused(address admin);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, address indexed from, uint256 amount);
    event Encumber(address indexed owner, address indexed taker, uint256 amount);
    event Initialized(uint8 version);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Paused(address account);
    event Release(address indexed owner, address indexed taker, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unpaused(address account);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function ENTITY_MAX_PERCENT_WAD() external view returns (uint256);
    function VERSION() external view returns (string memory);
    function accountingPause() external;
    function accountingPaused() external view returns (bool);
    function accountingUnpause() external;
    function admin() external view returns (address);
    function allowList() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function availableBalanceOf(address owner) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function bulkMint(address[] memory dsts, uint256[] memory amounts) external;
    function burn(uint256 amount) external;
    function burn(address src, uint256 amount) external;
    function decimals() external pure returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function encumber(address taker, uint256 amount) external;
    function encumberFrom(address owner, address taker, uint256 amount) external;
    function encumberedBalanceOf(address) external view returns (uint256);
    function encumbrances(address, address) external view returns (uint256);
    function entityMaxBalance() external view returns (uint256);
    function hasSufficientPermissions(address addr) external view returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(string memory _name, string memory _symbol) external;
    function mint(address dst, uint256 amount) external;
    function name() external view returns (string memory);
    function nonces(address) external view returns (uint256);
    function pause() external;
    function paused() external view returns (bool);
    function permit(address owner, address spender, uint256 amount, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external;
    function release(address owner, uint256 amount) external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function unpause() external;
}
