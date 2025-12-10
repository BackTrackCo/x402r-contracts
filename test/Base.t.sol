// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/simple/main/factory/EscrowFactory.sol";
import "../src/simple/main/escrow/Escrow.sol";
import "../src/simple/main/x402/DepositRelay.sol";
import "../src/simple/main/x402/FactoryRelay.sol";
import "../src/simple/interfaces/IERC3009.sol";

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

contract MockAToken {
    mapping(address => uint256) public balanceOf;
    MockERC20 public underlying;
    
    constructor(address _underlying) {
        underlying = MockERC20(_underlying);
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
    }
}

contract MockPool {
    MockERC20 public token;
    MockAToken public aToken;
    
    constructor(address _token, address _aToken) {
        token = MockERC20(_token);
        aToken = MockAToken(_aToken);
    }
    
    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        if (asset != address(token)) revert("Invalid asset");
        if (!token.transferFrom(msg.sender, address(this), amount)) revert("Transfer failed");
        aToken.mint(onBehalfOf, amount);
    }
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        if (asset != address(token)) revert("Invalid asset");
        uint256 aTokenBal = aToken.balanceOf(msg.sender);
        // Withdraw the requested amount, but if there's yield, we can withdraw more
        // For simplicity, just withdraw what's requested (principal) and yield separately
        uint256 withdrawAmount = amount <= aTokenBal ? amount : aTokenBal;
        aToken.burn(msg.sender, withdrawAmount);
        // Ensure we have enough tokens - mint if needed
        if (token.balanceOf(address(this)) < withdrawAmount) {
            token.mint(address(this), withdrawAmount - token.balanceOf(address(this)));
        }
        if (!token.transfer(to, withdrawAmount)) revert("Transfer failed");
        return withdrawAmount;
    }
    
    function accrueYield(address to, uint256 yieldAmount) external {
        aToken.mint(to, yieldAmount);
    }
}

contract BaseTest is Test {
    EscrowFactory public factory;
    DepositRelay public depositRelay;
    FactoryRelay public factoryRelay;
    
    MockERC3009 public token;
    MockAToken public aToken;
    MockPool public pool;
    
    address public defaultArbiter = address(0x1234);
    address public merchant = address(0x5678);
    address public user = address(0x9ABC);
    address public facilitator = address(0xDEF0);
    
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e6; // 1M USDC
    
    function setUp() public virtual {
        _deployMocks();
        _deployContracts();
        _setupBalances();
    }
    
    function _deployMocks() internal {
        token = new MockERC3009();
        aToken = new MockAToken(address(token));
        pool = new MockPool(address(token), address(aToken));
    }
    
    function _deployContracts() internal {
        factory = new EscrowFactory(
            defaultArbiter,
            address(token),
            address(aToken),
            address(pool)
        );
        depositRelay = new DepositRelay(address(token));
        factoryRelay = new FactoryRelay();
    }
    
    function _setupBalances() internal {
        token.mint(user, INITIAL_BALANCE);
        token.mint(address(pool), INITIAL_BALANCE * 10);
    }
    
    function registerMerchant() internal returns (address escrow) {
        return factory.registerMerchant(merchant);
    }
    
    function getEscrow() internal view returns (Escrow) {
        address escrowAddr = factory.getEscrow(merchant);
        return Escrow(escrowAddr);
    }
}

