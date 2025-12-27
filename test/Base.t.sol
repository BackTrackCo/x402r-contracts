// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {RelayProxy} from "../src/simple/main/x402/RelayProxy.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";
import {IERC3009} from "../src/simple/interfaces/IERC3009.sol";
import {CreateX} from "@createx/CreateX.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
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

// Mock aToken (rebasing token for Aave)
// In Aave, aTokens are rebasing - balanceOf() directly represents underlying amount
// When yield accrues, balances increase proportionally
// We use ERC20 balance as shares, and calculate underlying balance from exchange rate
contract MockAToken is ERC20 {
    MockERC20 public immutable UNDERLYING;
    uint256 private _totalAssets;
    
    constructor(address _underlying) ERC20("Mock aToken", "aToken") {
        UNDERLYING = MockERC20(_underlying);
        _totalAssets = 0;
    }
    
    // Override balanceOf to return underlying amount (rebasing)
    // balance = (shares * totalAssets) / totalSupply
    // where shares = ERC20 balance
    function balanceOf(address account) public view override returns (uint256) {
        uint256 shares = super.balanceOf(account); // Use ERC20 balance as shares
        if (shares == 0 || _totalAssets == 0 || totalSupply() == 0) {
            return 0;
        }
        return (shares * _totalAssets) / totalSupply();
    }
    
    // In Aave, aTokens are rebasing - balanceOf() returns underlying amount
    // We simulate this by tracking shares (ERC20 balance) and total assets
    function mint(address to, uint256 amount) external {
        uint256 currentAssets = _totalAssets;
        _totalAssets += amount;
        // Mint shares based on current exchange rate
        // If totalSupply is 0, mint 1:1
        // Otherwise: shares = (amount * totalSupply) / currentAssets
        uint256 shares = totalSupply() == 0 || currentAssets == 0
            ? amount
            : (amount * totalSupply()) / currentAssets;
        _mint(to, shares); // ERC20 balance = shares
    }
    
    function burn(address from, uint256 underlyingAmount) external {
        // Calculate shares to burn based on current exchange rate
        uint256 shares = _totalAssets > 0 && totalSupply() > 0
            ? (underlyingAmount * totalSupply()) / _totalAssets
            : underlyingAmount;
        _totalAssets -= underlyingAmount;
        _burn(from, shares);
    }
    
    // Simulate yield accrual by increasing total assets (rebasing)
    // In Aave, aTokens rebase automatically - all balances increase proportionally
    // No need to mint additional tokens - the exchange rate changes
    function accrueYield(uint256 yieldAmount) external {
        _totalAssets += yieldAmount;
        // Balances increase automatically via rebasing (balanceOf calculates from shares and totalAssets)
    }
    
    // Helper to add underlying tokens (for test setup)
    // This increases totalAssets without minting shares, which affects the exchange rate
    // This simulates having underlying tokens available for withdrawal
    function addUnderlying(uint256 amount) external {
        UNDERLYING.mint(address(this), amount);
        _totalAssets += amount;
        // Don't mint shares - this is just for ensuring withdrawals work
        // The exchange rate will change, making existing shares worth more
    }
    
    function getTotalAssets() external view returns (uint256) {
        return _totalAssets;
    }
}

// Mock Aave Pool for testing
contract MockAavePool is IPool {
    MockERC20 public immutable UNDERLYING;
    MockAToken public immutable ATOKEN;
    mapping(address => DataTypes.ReserveData) private reserves;
    
    constructor(address _underlying) {
        UNDERLYING = MockERC20(_underlying);
        ATOKEN = new MockAToken(_underlying);
        
        // Set up reserve data
        DataTypes.ReserveData memory reserveData;
        reserveData.aTokenAddress = address(ATOKEN);
        reserves[_underlying] = reserveData;
    }
    
    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external override {
        require(asset == address(UNDERLYING), "Invalid asset");
        require(amount > 0, "Zero amount");
        require(UNDERLYING.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Mint aTokens 1:1 (rebasing means balance = underlying)
        ATOKEN.mint(onBehalfOf, amount);
    }
    
    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        require(asset == address(UNDERLYING), "Invalid asset");
        require(amount > 0, "Zero amount");
        
        // Check aToken balance (rebasing - balance = underlying)
        uint256 aTokenBalance = ATOKEN.balanceOf(msg.sender);
        require(aTokenBalance >= amount, "Insufficient aToken balance");
        
        // Burn aTokens
        ATOKEN.burn(msg.sender, amount);
        
        // Transfer underlying
        require(UNDERLYING.transfer(to, amount), "Transfer failed");
        return amount;
    }
    
    function getReserveData(address asset) external view override returns (DataTypes.ReserveData memory) {
        return reserves[asset];
    }
    
    // Helper to simulate yield accrual
    function accrueYield(uint256 yieldAmount) external {
        ATOKEN.accrueYield(yieldAmount);
        // Also add underlying tokens to pool
        UNDERLYING.mint(address(this), yieldAmount);
    }
    
    // Helper to add underlying tokens (for test setup)
    function addUnderlying(uint256 amount) external {
        UNDERLYING.mint(address(this), amount);
        ATOKEN.addUnderlying(amount);
    }
    
    // Stub implementations for other IPool functions (not used in tests)
    function mintUnbacked(address, uint256, address, uint16) external pure override {
        revert("Not implemented");
    }
    
    function backUnbacked(address, uint256, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function supplyWithPermit(address, uint256, address, uint16, uint256, uint8, bytes32, bytes32) external pure override {
        revert("Not implemented");
    }
    
    function borrow(address, uint256, uint256, uint16, address) external pure override {
        revert("Not implemented");
    }
    
    function repay(address, uint256, uint256, address) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function repayWithPermit(address, uint256, uint256, address, uint256, uint8, bytes32, bytes32) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function repayWithATokens(address, uint256, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function swapBorrowRateMode(address, uint256) external pure override {
        revert("Not implemented");
    }
    
    function rebalanceStableBorrowRate(address, address) external pure override {
        revert("Not implemented");
    }
    
    function setUserUseReserveAsCollateral(address, bool) external pure override {
        revert("Not implemented");
    }
    
    function liquidationCall(address, address, address, uint256, bool) external pure override {
        revert("Not implemented");
    }
    
    function flashLoan(address, address[] calldata, uint256[] calldata, uint256[] calldata, address, bytes calldata, uint16) external pure override {
        revert("Not implemented");
    }
    
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external pure override {
        revert("Not implemented");
    }
    
    function getUserAccountData(address) external pure override returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        revert("Not implemented");
    }
    
    function initReserve(address, address, address, address, address) external pure override {
        revert("Not implemented");
    }
    
    function dropReserve(address) external pure override {
        revert("Not implemented");
    }
    
    function setReserveInterestRateStrategyAddress(address, address) external pure override {
        revert("Not implemented");
    }
    
    function setConfiguration(address, DataTypes.ReserveConfigurationMap memory) external pure override {
        revert("Not implemented");
    }
    
    function getConfiguration(address) external pure override returns (DataTypes.ReserveConfigurationMap memory) {
        revert("Not implemented");
    }
    
    function getUserConfiguration(address) external pure override returns (DataTypes.UserConfigurationMap memory) {
        revert("Not implemented");
    }
    
    function getReserveNormalizedIncome(address) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function getReserveNormalizedVariableDebt(address) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external pure override {
        revert("Not implemented");
    }
    
    function getReservesList() external pure override returns (address[] memory) {
        revert("Not implemented");
    }
    
    function getReserveAddressById(uint16) external pure override returns (address) {
        revert("Not implemented");
    }
    
    function mintToTreasury(address[] calldata) external pure override {
        revert("Not implemented");
    }
    
    function deposit(address, uint256, address, uint16) external pure override {
        revert("Not implemented");
    }
    
    function ADDRESSES_PROVIDER() external pure override returns (IPoolAddressesProvider) {
        revert("Not implemented");
    }
    
    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function FLASHLOAN_PREMIUM_TOTAL() external pure override returns (uint128) {
        revert("Not implemented");
    }
    
    function BRIDGE_PROTOCOL_FEE() external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function FLASHLOAN_PREMIUM_TO_PROTOCOL() external pure override returns (uint128) {
        revert("Not implemented");
    }
    
    function MAX_NUMBER_RESERVES() external pure override returns (uint16) {
        revert("Not implemented");
    }
    
    function updateBridgeProtocolFee(uint256) external pure override {
        revert("Not implemented");
    }
    
    function updateFlashloanPremiums(uint128, uint128) external pure override {
        revert("Not implemented");
    }
    
    function configureEModeCategory(uint8, DataTypes.EModeCategory memory) external pure override {
        revert("Not implemented");
    }
    
    function getEModeCategoryData(uint8) external pure override returns (DataTypes.EModeCategory memory) {
        revert("Not implemented");
    }
    
    function setUserEMode(uint8) external pure override {
        revert("Not implemented");
    }
    
    function getUserEMode(address) external pure override returns (uint256) {
        revert("Not implemented");
    }
    
    function resetIsolationModeTotalDebt(address) external pure override {
        revert("Not implemented");
    }
    
    function rescueTokens(address, address, uint256) external pure override {
        revert("Not implemented");
    }
}

contract BaseTest is Test {
    DepositRelayFactory public factory;
    Escrow public escrow;
    CreateX public createx;
    
    MockERC3009 public token;
    MockAavePool public pool;
    
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
        pool = new MockAavePool(address(token));
    }
    
    function _deployContracts() internal {
        // Deploy CreateX for CREATE3
        createx = new CreateX();
        
        // Deploy shared escrow with Aave Pool
        escrow = new Escrow(
            address(token),
            address(pool)
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
        // No need to pre-fund Aave pool - it gets tokens from deposits
        // The pool will have underlying tokens available from the supply() calls
    }
    
    function _registerMerchant() internal {
        // Register merchant with shared escrow (merchant must call it themselves)
        vm.prank(merchant);
        escrow.registerMerchant(defaultArbiter);
    }
    
    function deployRelay() internal returns (address) {
        return factory.deployRelay(merchant);
    }
    
    function getRelay() internal view returns (address) {
        return factory.getRelayAddress(merchant);
    }
}
