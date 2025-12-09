// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Aave v3 interfaces
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IAToken} from "@aave-v3-core/interfaces/IAToken.sol";

import {EscrowAccess} from "./EscrowAccess.sol";

contract Escrow is EscrowAccess {
    struct Deposit {
        uint256 principal;   // Principal amount
        uint256 timestamp;   // Deposit timestamp
        uint256 nonce;       // Unique nonce for this deposit
    }

    IERC20 public immutable token;     // e.g. USDC
    IPool public immutable pool;       // Aave pool
    IAToken public immutable aToken;   // aUSDC or equivalent

    uint256 public constant RELEASE_DELAY = 3 days;

    // user → depositNonce → deposit info
    mapping(address => mapping(uint256 => Deposit)) public deposits;
    // user → array of deposit nonces (for iteration)
    mapping(address => uint256[]) public userDepositNonces;
    // user → next deposit nonce (ensures uniqueness even in same block)
    mapping(address => uint256) public userDepositNonce;
    uint256 public totalPrincipal;

    event DepositCreated(address indexed user, uint256 amount, uint256 nonce);
    event DepositReleased(address indexed user, address indexed merchant, uint256 principal, uint256 yield, uint256 nonce);
    event DepositRefunded(address indexed user, address indexed refundedBy, uint256 principal, uint256 yield, uint256 nonce);

    constructor(
        address _merchantPayout,
        address _arbiter,
        address _token,
        address _aToken,
        address _pool
    ) EscrowAccess(_merchantPayout, _arbiter) {
        require(_token != address(0), "Zero token");
        require(_aToken != address(0), "Zero aToken");
        require(_pool != address(0), "Zero pool");

        token = IERC20(_token);
        aToken = IAToken(_aToken);
        pool = IPool(_pool);
    }

    /// @notice Calculate yield for a deposit (proportional to principal)
    /// @dev Must be called BEFORE clearing the deposit from storage
    function _calculateYield(uint256 principalAmount) internal view returns (uint256) {
        if (totalPrincipal == 0) return 0;
        
        uint256 totalBal = aToken.balanceOf(address(this));
        if (totalBal <= totalPrincipal) return 0;
        
        // Simple proportional distribution: (excess * principal) / totalPrincipal
        return ((totalBal - totalPrincipal) * principalAmount) / totalPrincipal;
    }

    /// @notice Withdraw principal and distribute yield
    /// @param to Address to receive the principal
    /// @param principalAmount Amount of principal to withdraw
    /// @param yieldAmount Pre-calculated yield amount (calculated before clearing deposit)
    function _withdrawAndDistribute(
        address to,
        uint256 principalAmount,
        uint256 yieldAmount
    ) internal {
        // Update total principal before withdrawal
        totalPrincipal -= principalAmount;
        
        // Withdraw principal to recipient
        pool.withdraw(address(token), principalAmount, to);
        
        // Withdraw yield to arbiter (if any)
        if (yieldAmount > 0) {
            pool.withdraw(address(token), yieldAmount, arbiter);
        }
    }

    function _clearDeposit(address user, uint256 depositNonce) internal {
        delete deposits[user][depositNonce];
        
        // Remove deposit nonce from user's array
        uint256[] storage nonces = userDepositNonces[user];
        uint256 length = nonces.length;
        for (uint256 i = 0; i < length; i++) {
            if (nonces[i] == depositNonce) {
                nonces[i] = nonces[length - 1];
                nonces.pop();
                break;
            }
        }
    }

    function noteDeposit(address user, uint256 amount)
        external
        returns (uint256 depositNonce)
    {
        require(user != address(0), "Zero user");
        require(amount > 0, "Zero amount");
        
        // Get and increment the nonce for this user (ensures uniqueness even in same block)
        depositNonce = userDepositNonce[user];
        userDepositNonce[user]++;
        
        // Ensure deposit doesn't already exist at this nonce (should never happen, but safety check)
        require(deposits[user][depositNonce].principal == 0, "Deposit at nonce already exists");
        
        deposits[user][depositNonce] = Deposit({
            principal: amount,
            timestamp: block.timestamp,
            nonce: depositNonce
        });
        userDepositNonces[user].push(depositNonce);
        totalPrincipal += amount;

        token.approve(address(pool), amount);
        pool.supply(address(token), amount, address(this), 0);

        emit DepositCreated(user, amount, depositNonce);
    }
    
    /// @notice Get the latest deposit nonce for a user
    /// @param user The user address
    /// @return The nonce of the most recent deposit, or 0 if no deposits exist
    function getLatestDepositNonce(address user) external view returns (uint256) {
        uint256[] storage nonces = userDepositNonces[user];
        if (nonces.length == 0) {
            return 0;
        }
        return nonces[nonces.length - 1];
    }

    /// @notice Release principal to merchant after 3 day release delay (anyone can call)
    /// @param user The user address whose deposit should be released
    /// @param depositNonce The nonce of the deposit to release
    function release(address user, uint256 depositNonce) external {
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        require(
            block.timestamp >= deposit.timestamp + RELEASE_DELAY,
            "Too early"
        );
        
        uint256 amt = deposit.principal;
        
        // CRITICAL: Calculate yield BEFORE clearing the deposit
        // This ensures the deposit is included in totalPrincipal for proportional calculation
        uint256 yieldAmount = _calculateYield(amt);
        
        // Now clear the deposit (removes it from mapping and array)
        _clearDeposit(user, depositNonce);
        
        // Withdraw principal and yield
        _withdrawAndDistribute(merchantPayout, amt, yieldAmount);
        
        emit DepositReleased(user, merchantPayout, amt, yieldAmount, depositNonce);
    }

    /// @notice Refund principal to user (merchant or arbiter can call)
    /// @param user The user address whose deposit should be refunded
    /// @param depositNonce The nonce of the deposit to refund
    function refund(address user, uint256 depositNonce) external onlyMerchantOrArbiter {
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        
        uint256 amt = deposit.principal;
        
        // CRITICAL: Calculate yield BEFORE clearing the deposit
        // This ensures the deposit is included in totalPrincipal for proportional calculation
        uint256 yieldAmount = _calculateYield(amt);
        
        // Now clear the deposit (removes it from mapping and array)
        _clearDeposit(user, depositNonce);
        
        // Withdraw principal and yield
        _withdrawAndDistribute(user, amt, yieldAmount);
        
        emit DepositRefunded(user, msg.sender, amt, yieldAmount, depositNonce);
    }
}

