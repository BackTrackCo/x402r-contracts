// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {EscrowAccess} from "./EscrowAccess.sol";

contract Escrow is EscrowAccess, ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct Deposit {
        uint256 principal;   // Principal amount
        uint256 timestamp;   // Deposit timestamp
        uint256 nonce;       // Unique nonce for this deposit
        address merchantPayout; // Merchant payout address (for shared escrow)
    }

    enum RequestStatus { Pending, Approved, Rejected }

    struct RefundRequest {
        address user;
        uint256 depositNonce;
        string ipfsLink;
        RequestStatus status;
    }

    IERC20 public immutable TOKEN;     // e.g. USDC

    uint256 public constant RELEASE_DELAY = 3 days;

    // user → depositNonce → deposit info
    mapping(address => mapping(uint256 => Deposit)) public deposits;
    // user → array of deposit nonces (for iteration)
    mapping(address => uint256[]) public userDepositNonces;
    // user → next deposit nonce (ensures uniqueness even in same block)
    mapping(address => uint256) public userDepositNonce;
    uint256 public totalPrincipal;

    // user → depositNonce → refund request
    mapping(address => mapping(uint256 => RefundRequest)) public refundRequests;

    event DepositCreated(address indexed user, uint256 amount, uint256 nonce);
    event DepositReleased(address indexed user, address indexed merchant, uint256 principal, uint256 yield, uint256 nonce);
    event DepositRefunded(address indexed user, address indexed refundedBy, uint256 principal, uint256 yield, uint256 nonce);
    event RefundRequestCreated(address indexed user, uint256 depositNonce, string ipfsLink);
    event RefundRequestStatusChanged(address indexed user, uint256 depositNonce, RequestStatus status);
    
    // Debugging events for noteDeposit
    event NoteDepositStarted(address indexed user, address indexed merchantPayout, uint256 amount);
    event NoteDepositBalanceCheck(uint256 balance, uint256 required);
    event NoteDepositApprovalCheck(uint256 allowance, uint256 required);
    event NoteDepositSupplyAttempt(address indexed vault, address indexed token, uint256 amount);
    event NoteDepositError(string reason, uint256 balance, uint256 allowance);

    constructor(
        address _merchantPayout,
        address _arbiter,
        address _token
    ) EscrowAccess(_merchantPayout, _arbiter) {
        require(_token != address(0), "Zero token");

        TOKEN = IERC20(_token);
    }

    /// @notice Calculate yield for a deposit (proportional to principal)
    /// @dev Must be called BEFORE clearing the deposit from storage
    /// @param principalAmount The principal amount of the deposit
    /// @param merchantPayout The merchant payout address (to get the vault)
    function _calculateYield(uint256 principalAmount, address merchantPayout) internal view returns (uint256) {
        if (totalPrincipal == 0) return 0;
        
        // Get the merchant's vault
        address vaultAddress = merchantVaults[merchantPayout];
        require(vaultAddress != address(0), "Escrow: Merchant vault not configured");
        IERC4626 vault = IERC4626(vaultAddress);
        
        // Get total assets in vault (includes yield)
        uint256 totalAssets = vault.totalAssets();
        if (totalAssets <= totalPrincipal) return 0;
        
        // Simple proportional distribution: (excess * principal) / totalPrincipal
        return ((totalAssets - totalPrincipal) * principalAmount) / totalPrincipal;
    }

    /// @notice Withdraw principal and distribute yield
    /// @param to Address to receive the principal
    /// @param principalAmount Amount of principal to withdraw
    /// @param yieldAmount Pre-calculated yield amount (calculated before clearing deposit)
    /// @param merchantPayout The merchant payout address (for shared escrow, determines arbiter and vault)
    function _withdrawAndDistribute(
        address to,
        uint256 principalAmount,
        uint256 yieldAmount,
        address merchantPayout
    ) internal {
        // Update total principal before withdrawal
        totalPrincipal -= principalAmount;
        
        // Get the merchant's vault
        address vaultAddress = merchantVaults[merchantPayout];
        require(vaultAddress != address(0), "Escrow: Merchant vault not configured");
        IERC4626 vault = IERC4626(vaultAddress);
        
        // Withdraw principal to recipient using ERC4626 vault
        vault.withdraw(principalAmount, to, address(this));
        
        // Withdraw yield to arbiter (if any)
        if (yieldAmount > 0) {
            address arbiter;
            // Support both per-merchant (immutable) and shared (mapping) escrows
            if (ARBITER != address(0)) {
                arbiter = ARBITER;
            } else {
                arbiter = merchantArbiters[merchantPayout];
                require(arbiter != address(0), "Merchant not registered");
            }
            vault.withdraw(yieldAmount, arbiter, address(this));
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

    /// @notice Note a deposit (backward compatible - uses MERCHANT_PAYOUT if set)
    /// @param user The user making the deposit
    /// @param amount The deposit amount
    /// @return depositNonce The nonce for this deposit
    function noteDeposit(address user, uint256 amount)
        external
        returns (uint256 depositNonce)
    {
        // For backward compatibility, use MERCHANT_PAYOUT if set
        address merchantPayout = MERCHANT_PAYOUT;
        require(merchantPayout != address(0), "Use noteDeposit(user, merchantPayout, amount)");
        return noteDeposit(user, merchantPayout, amount);
    }

    /// @notice Note a deposit with merchantPayout (for shared escrow)
    /// @param user The user making the deposit
    /// @param merchantPayout The merchant payout address
    /// @param amount The deposit amount
    /// @return depositNonce The nonce for this deposit
    function noteDeposit(address user, address merchantPayout, uint256 amount)
        public
        nonReentrant
        returns (uint256 depositNonce)
    {
        emit NoteDepositStarted(user, merchantPayout, amount);
        
        require(user != address(0), "Escrow: Zero user");
        require(merchantPayout != address(0), "Escrow: Zero merchant payout");
        require(amount > 0, "Escrow: Zero amount");
        
        // For shared escrow, verify merchant is registered
        if (MERCHANT_PAYOUT == address(0)) {
            require(registeredMerchants[merchantPayout], "Escrow: Merchant not registered");
        }
        
        // Get the merchant's vault (or use default for per-merchant escrows)
        IERC4626 vault;
        if (MERCHANT_PAYOUT != address(0)) {
            // Per-merchant escrow - not supported (no default vault)
            revert("Escrow: Per-merchant escrow not supported without vault");
        } else {
            // Shared escrow - get merchant's configured vault
            address vaultAddress = merchantVaults[merchantPayout];
            require(vaultAddress != address(0), "Escrow: Merchant vault not configured");
            vault = IERC4626(vaultAddress);
        }
        
        // Verify vault uses the correct underlying asset
        require(vault.asset() == address(TOKEN), "Escrow: Vault asset mismatch");
        
        // Get and increment the nonce for this user (ensures uniqueness even in same block)
        depositNonce = userDepositNonce[user];
        userDepositNonce[user]++;
        
        // Ensure deposit doesn't already exist at this nonce (should never happen, but safety check)
        require(deposits[user][depositNonce].principal == 0, "Escrow: Deposit at nonce already exists");
        
        // Verify escrow has received the tokens before proceeding
        uint256 balanceBefore = TOKEN.balanceOf(address(this));
        emit NoteDepositBalanceCheck(balanceBefore, amount);
        require(balanceBefore >= amount, "Escrow: Insufficient token balance");
        
        deposits[user][depositNonce] = Deposit({
            principal: amount,
            timestamp: block.timestamp,
            nonce: depositNonce,
            merchantPayout: merchantPayout
        });
        userDepositNonces[user].push(depositNonce);
        totalPrincipal += amount;

        // Approve vault to spend tokens using SafeERC20
        // forceApprove handles tokens that require resetting approval to zero first (like USDT)
        TOKEN.forceApprove(address(vault), amount);
        
        // Verify approval was successful
        uint256 allowance = TOKEN.allowance(address(this), address(vault));
        emit NoteDepositApprovalCheck(allowance, amount);
        require(allowance >= amount, "Escrow: Insufficient allowance after approval");
        
        // Attempt to deposit tokens into ERC4626 vault
        emit NoteDepositSupplyAttempt(address(vault), address(TOKEN), amount);
        try vault.deposit(amount, address(this)) returns (uint256 shares) {
            // Success - emit deposit created event
            // shares received from vault (for logging/debugging)
            emit DepositCreated(user, amount, depositNonce);
        } catch Error(string memory reason) {
            // Revert with detailed error message
            emit NoteDepositError(reason, balanceBefore, allowance);
            revert(string(abi.encodePacked("Escrow: VAULT.deposit failed - ", reason)));
        } catch {
            // Handle low-level revert (no reason string)
            emit NoteDepositError("Low-level revert", balanceBefore, allowance);
            revert("Escrow: VAULT.deposit failed with low-level revert");
        }
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
        address merchantPayout = deposit.merchantPayout;
        
        // For backward compatibility, use MERCHANT_PAYOUT if merchantPayout is zero
        if (merchantPayout == address(0)) {
            merchantPayout = MERCHANT_PAYOUT;
            require(merchantPayout != address(0), "No merchant payout");
        }
        
        // CRITICAL: Calculate yield BEFORE clearing the deposit
        // This ensures the deposit is included in totalPrincipal for proportional calculation
        uint256 yieldAmount = _calculateYield(amt, merchantPayout);
        
        // Now clear the deposit (removes it from mapping and array)
        _clearDeposit(user, depositNonce);
        
        // Withdraw principal and yield
        _withdrawAndDistribute(merchantPayout, amt, yieldAmount, merchantPayout);
        
        emit DepositReleased(user, merchantPayout, amt, yieldAmount, depositNonce);
    }

    /// @notice Refund principal to user (merchant or arbiter can call)
    /// @param user The user address whose deposit should be refunded
    /// @param depositNonce The nonce of the deposit to refund
    function refund(address user, uint256 depositNonce) external {
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        
        address merchantPayout = deposit.merchantPayout;
        
        // For backward compatibility, use MERCHANT_PAYOUT if merchantPayout is zero
        if (merchantPayout == address(0)) {
            merchantPayout = MERCHANT_PAYOUT;
            require(merchantPayout != address(0), "No merchant payout");
            // Use old access control for backward compatibility
            require(
                msg.sender == MERCHANT_PAYOUT || msg.sender == ARBITER,
                "Not merchant or arbiter"
            );
        } else {
            // Use new access control for shared escrow
            _checkMerchantOrArbiter(merchantPayout);
        }
        
        uint256 amt = deposit.principal;
        
        // CRITICAL: Calculate yield BEFORE clearing the deposit
        // This ensures the deposit is included in totalPrincipal for proportional calculation
        uint256 yieldAmount = _calculateYield(amt, merchantPayout);
        
        // Now clear the deposit (removes it from mapping and array)
        _clearDeposit(user, depositNonce);
        
        // Withdraw principal and yield
        _withdrawAndDistribute(user, amt, yieldAmount, merchantPayout);
        
        emit DepositRefunded(user, msg.sender, amt, yieldAmount, depositNonce);
    }

    /// @notice Request a refund for a deposit (only the user who made the deposit can call)
    /// @param depositNonce The nonce of the deposit to request refund for
    /// @param ipfsLink IPFS link to additional information (e.g., images, documents)
    function requestRefund(uint256 depositNonce, string calldata ipfsLink) external {
        address user = msg.sender;
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        
        // Check if request already exists (user field will be non-zero if request exists)
        RefundRequest storage existingRequest = refundRequests[user][depositNonce];
        require(existingRequest.user == address(0), "Request already exists");
        
        // Create new request
        refundRequests[user][depositNonce] = RefundRequest({
            user: user,
            depositNonce: depositNonce,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending
        });
        
        emit RefundRequestCreated(user, depositNonce, ipfsLink);
    }

    /// @notice Get refund request details
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    /// @return The refund request struct
    function getRefundRequest(address user, uint256 depositNonce) external view returns (RefundRequest memory) {
        return refundRequests[user][depositNonce];
    }
}

