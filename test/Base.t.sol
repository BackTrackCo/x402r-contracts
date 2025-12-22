// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {RelayProxy} from "../src/simple/main/x402/RelayProxy.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";
import {IERC3009} from "../src/simple/interfaces/IERC3009.sol";
import {CreateX} from "@createx/CreateX.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock contracts
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    
    uint256 public totalSupply;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockERC3009 is MockERC20, IERC3009 {
    mapping(bytes32 => bool) public usedNonces;
    
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external override {
        require(block.timestamp >= validAfter, "Not yet valid");
        require(block.timestamp <= validBefore, "Expired");
        require(!usedNonces[nonce], "Nonce already used");
        usedNonces[nonce] = true;
        
        // Simple mock - just transfer
        require(balanceOf[from] >= value, "Insufficient balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
    }
}

// Simple ERC4626 mock vault for testing
contract MockERC4626 is ERC20, IERC4626 {
    MockERC20 public immutable assetToken;
    uint256 private _totalAssets;
    
    constructor(address _asset) ERC20("Mock Vault", "MV") {
        assetToken = MockERC20(_asset);
        _totalAssets = 0;
    }
    
    function asset() external view override returns (address) {
        return address(assetToken);
    }
    
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }
    
    function convertToShares(uint256 assets) external view override returns (uint256) {
        if (_totalAssets == 0) return assets; // 1:1 initially
        return (assets * totalSupply()) / _totalAssets;
    }
    
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        if (totalSupply() == 0) return shares; // 1:1 initially
        return (shares * _totalAssets) / totalSupply();
    }
    
    function maxDeposit(address) external pure override returns (uint256) {
        return type(uint256).max;
    }
    
    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return this.convertToShares(assets);
    }
    
    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        require(assets > 0, "Zero assets");
        require(assetToken.transferFrom(msg.sender, address(this), assets), "Transfer failed");
        
        uint256 shares = _totalAssets == 0 ? assets : (assets * totalSupply()) / _totalAssets;
        _totalAssets += assets;
        _mint(receiver, shares);
        return shares;
    }
    
    function maxMint(address) external pure override returns (uint256) {
        return type(uint256).max;
    }
    
    function previewMint(uint256 shares) external view override returns (uint256) {
        return this.convertToAssets(shares);
    }
    
    function mint(uint256 shares, address receiver) external override returns (uint256) {
        uint256 assets = _totalAssets == 0 ? shares : (shares * _totalAssets) / totalSupply();
        return this.deposit(assets, receiver);
    }
    
    function maxWithdraw(address owner) external view override returns (uint256) {
        return this.convertToAssets(balanceOf(owner));
    }
    
    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        return this.convertToShares(assets);
    }
    
    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256) {
        uint256 shares = _totalAssets == 0 ? assets : (assets * totalSupply()) / _totalAssets;
        if (msg.sender != owner) {
            // In real ERC4626, would check allowance here
        }
        _burn(owner, shares);
        _totalAssets -= assets;
        require(assetToken.transfer(receiver, assets), "Transfer failed");
        return shares;
    }
    
    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }
    
    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return this.convertToAssets(shares);
    }
    
    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256) {
        uint256 assets = _totalAssets == 0 ? shares : (shares * _totalAssets) / totalSupply();
        if (msg.sender != owner) {
            // In real ERC4626, would check allowance here
        }
        _burn(owner, shares);
        _totalAssets -= assets;
        require(assetToken.transfer(receiver, assets), "Transfer failed");
        return assets;
    }
    
    // Helper function to simulate yield accrual
    function accrueYield(uint256 yieldAmount) external {
        _totalAssets += yieldAmount;
    }
    
    // Helper to mint underlying tokens to vault (for testing)
    // This increases both tokens and _totalAssets (simulates deposits or yield)
    function mintUnderlying(uint256 amount) external {
        assetToken.mint(address(this), amount);
        _totalAssets += amount;
    }
    
    // Helper to add tokens to vault without increasing _totalAssets (for test setup)
    // This is used to ensure vault has tokens for withdrawals without affecting yield calculations
    function addTokens(uint256 amount) external {
        assetToken.mint(address(this), amount);
        // Don't increase _totalAssets - this is just for ensuring withdrawals work
    }
}

contract BaseTest is Test {
    DepositRelayFactory public factory;
    Escrow public escrow;
    CreateX public createx;
    
    MockERC3009 public token;
    MockERC4626 public vault;
    
    address public defaultArbiter = address(0x1234);
    address public merchant = address(0x5678);
    address public user = address(0x9ABC);
    address public facilitator = address(0xDEF0);
    
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e6; // 1M USDC
    
    function setUp() public virtual {
        _deployMocks();
        _deployContracts();
        _setupBalances();
        _registerMerchant();
    }
    
    function _deployMocks() internal {
        token = new MockERC3009();
        vault = new MockERC4626(address(token));
    }
    
    function _deployContracts() internal {
        // Deploy CreateX for CREATE3
        createx = new CreateX();
        
        // Deploy shared escrow (merchantPayout = 0, arbiter = 0 for shared escrow)
        escrow = new Escrow(
            address(0), // merchantPayout = 0 (shared escrow)
            address(0),  // arbiter = 0 (merchants register separately)
            address(token)
        );
        
        // Deploy factory (uses CreateX and merchant address as salt; fresh factory per version)
        factory = new DepositRelayFactory(
            address(token),
            address(escrow),
            address(createx)
        );
    }
    
    function _setupBalances() internal {
        token.mint(user, INITIAL_BALANCE);
        // Add tokens to vault for withdrawals without affecting _totalAssets (for accurate yield calculations)
        vault.addTokens(INITIAL_BALANCE * 10);
    }
    
    function _registerMerchant() internal {
        // Register merchant with shared escrow (merchant must call it themselves)
        // Include vault address in registration
        vm.prank(merchant);
        escrow.registerMerchant(defaultArbiter, address(vault));
    }
    
    function deployRelay() internal returns (address) {
        return factory.deployRelay(merchant);
    }
    
    function getRelay() internal view returns (address) {
        return factory.getRelayAddress(merchant);
    }
}
