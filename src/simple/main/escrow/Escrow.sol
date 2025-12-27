// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";

import {EscrowAccess} from "./EscrowAccess.sol";

contract Escrow is EscrowAccess {
    using SafeERC20 for IERC20;
    struct Deposit {
        uint256 principal;   // Principal amount
        uint256 timestamp;   // Deposit timestamp
        uint256 nonce;       // Unique nonce for this deposit
        address merchantPayout; // Merchant payout address
    }

    IERC20 public immutable TOKEN;     // e.g. USDC
    IPool public immutable POOL;       // Aave Pool contract
    address public immutable ATOKEN;   // Aave aToken address for TOKEN

    uint256 public constant RELEASE_DELAY = 3 days;

    // user → depositNonce → deposit info
    mapping(address => mapping(uint256 => Deposit)) private deposits;
    // user → array of deposit nonces (for iteration)
    mapping(address => uint256[]) private userDepositNonces;
    // user → next deposit nonce (ensures uniqueness even in same block)
    mapping(address => uint256) private userDepositNonce;
    uint256 public totalPrincipal;

    event DepositCreated(address indexed user, uint256 amount, uint256 nonce);
    event DepositReleased(address indexed user, address indexed merchant, uint256 principal, uint256 yield, uint256 nonce);
    event DepositRefunded(address indexed user, address indexed refundedBy, uint256 principal, uint256 yield, uint256 nonce);

    constructor(
        address _token,
        address _pool
    ) EscrowAccess() {
        require(_token != address(0), "Zero token");
        require(_pool != address(0), "Zero pool");

        TOKEN = IERC20(_token);
        POOL = IPool(_pool);
        
        // Get aToken address from Aave Pool
        DataTypes.ReserveData memory reserveData = POOL.getReserveData(_token);
        require(reserveData.aTokenAddress != address(0), "Escrow: Asset not supported by Aave");
        ATOKEN = reserveData.aTokenAddress;
        
        // Verify aToken uses the correct underlying asset
        // Note: aTokens in Aave V3 have an UNDERLYING_ASSET_ADDRESS() function
        // We'll verify this works correctly in practice
    }

    /// @notice Calculate yield for a deposit (proportional to principal)
    /// @dev Must be called BEFORE clearing the deposit from storage
    /// @param principalAmount The principal amount of the deposit
    /// @return The calculated yield amount
    function _calculateYield(uint256 principalAmount) internal view returns (uint256) {
        if (totalPrincipal == 0) return 0;
        
        // Get total underlying assets from aToken balance (aTokens are rebasing)
        uint256 totalAssets = IERC20(ATOKEN).balanceOf(address(this));
        if (totalAssets <= totalPrincipal) return 0;
        
        // Proportional distribution: (excess * principal) / totalPrincipal
        return ((totalAssets - totalPrincipal) * principalAmount) / totalPrincipal;
    }

    /// @notice Withdraw principal and distribute yield
    /// @param to Address to receive the principal
    /// @param principalAmount Amount of principal to withdraw
    /// @param yieldAmount Pre-calculated yield amount (calculated before clearing deposit)
    /// @param merchantPayout The merchant payout address (determines arbiter)
    /// @return actualPrincipal The actual principal amount withdrawn
    /// @return actualYield The actual yield amount withdrawn
    /// @dev Requires full principal to be available - reverts if vault has lost value.
    ///      This protects users from silent losses. Yield can be partial if insufficient.
    function _withdrawAndDistribute(
        address to,
        uint256 principalAmount,
        uint256 yieldAmount,
        address merchantPayout
    ) internal returns (uint256 actualPrincipal, uint256 actualYield) {
        totalPrincipal -= principalAmount;
        
        // Check if we can provide full principal - aToken balance represents total underlying
        // In Aave, aTokens are rebasing, so balanceOf() gives underlying amount
        uint256 totalAssets = IERC20(ATOKEN).balanceOf(address(this));
        require(totalAssets >= principalAmount, "Escrow: Aave insufficient balance - cannot refund full principal");
        
        // Withdraw full principal from Aave Pool
        // Aave withdraw returns the actual amount withdrawn (should be >= principalAmount)
        actualPrincipal = POOL.withdraw(address(TOKEN), principalAmount, to);
        // Aave should return at least the requested amount (or very close due to rounding)
        // We allow small rounding differences but require it to be very close
        require(actualPrincipal >= principalAmount - 1, "Escrow: Aave withdrawal returned less than requested");
        
        // Distribute yield if available (yield can be partial if insufficient)
        if (yieldAmount > 0) {
            address arbiter = merchantArbiters[merchantPayout];
            require(arbiter != address(0), "Merchant not registered");
            
            // Check how much we can withdraw for yield after principal withdrawal
            uint256 totalAssetsAfter = IERC20(ATOKEN).balanceOf(address(this));
            actualYield = yieldAmount > totalAssetsAfter ? totalAssetsAfter : yieldAmount;
            
            // Only withdraw yield if we have enough
            if (actualYield > 0) {
                uint256 withdrawnYield = POOL.withdraw(address(TOKEN), actualYield, arbiter);
                // Use the actual amount withdrawn (should be >= actualYield, but use what we got)
                actualYield = withdrawnYield;
            }
        }
    }

    /// @notice Clear a deposit from storage
    /// @param user The user address
    /// @param depositNonce The deposit nonce to clear
    function _clearDeposit(address user, uint256 depositNonce) internal {
        delete deposits[user][depositNonce];
        
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

    /// @notice Note a deposit with merchantPayout
    /// @param user The user making the deposit
    /// @param merchantPayout The merchant payout address
    /// @param amount The deposit amount
    /// @return depositNonce The nonce for this deposit
    function noteDeposit(address user, address merchantPayout, uint256 amount)
        public
        returns (uint256 depositNonce)
    {
        require(user != address(0), "Escrow: Zero user");
        require(merchantPayout != address(0), "Escrow: Zero merchant payout");
        require(amount > 0, "Escrow: Zero amount");
        require(registeredMerchants[merchantPayout], "Escrow: Merchant not registered");
        
        depositNonce = userDepositNonce[user];
        userDepositNonce[user]++;
        
        require(deposits[user][depositNonce].principal == 0, "Escrow: Deposit at nonce already exists");
        require(TOKEN.balanceOf(address(this)) >= amount, "Escrow: Insufficient token balance");
        
        deposits[user][depositNonce] = Deposit({
            principal: amount,
            timestamp: block.timestamp,
            nonce: depositNonce,
            merchantPayout: merchantPayout
        });
        userDepositNonces[user].push(depositNonce);
        totalPrincipal += amount;

        // Approve Aave Pool to spend tokens
        TOKEN.forceApprove(address(POOL), amount);
        require(TOKEN.allowance(address(this), address(POOL)) >= amount, "Escrow: Insufficient allowance");
        
        // Supply to Aave Pool (referral code = 0)
        POOL.supply(address(TOKEN), amount, address(this), 0);
        emit DepositCreated(user, amount, depositNonce);
    }
    
    /// @notice Get all deposits for a user
    /// @param user The user address
    /// @return nonces Array of deposit nonces
    /// @return depositData Array of deposit structs corresponding to each nonce
    function getUserDeposits(address user) external view returns (uint256[] memory nonces, Deposit[] memory depositData) {
        nonces = userDepositNonces[user];
        depositData = new Deposit[](nonces.length);
        
        for (uint256 i = 0; i < nonces.length; i++) {
            depositData[i] = deposits[user][nonces[i]];
        }
    }

    /// @notice Get a specific deposit
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    /// @return principal The principal amount
    /// @return timestamp The deposit timestamp
    /// @return nonce The deposit nonce
    /// @return merchantPayout The merchant payout address
    function getDeposit(address user, uint256 depositNonce) external view returns (uint256 principal, uint256 timestamp, uint256 nonce, address merchantPayout) {
        Deposit memory deposit = deposits[user][depositNonce];
        return (deposit.principal, deposit.timestamp, deposit.nonce, deposit.merchantPayout);
    }

    /// @notice Release principal to merchant after release delay (anyone can call)
    /// @param user The user address whose deposit should be released
    /// @param depositNonce The nonce of the deposit to release
    function release(address user, uint256 depositNonce) external {
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        require(block.timestamp >= deposit.timestamp + RELEASE_DELAY, "Too early");
        require(deposit.merchantPayout != address(0), "No merchant payout");
        
        uint256 principalAmount = deposit.principal;
        address merchantPayout = deposit.merchantPayout;
        
        // Calculate yield BEFORE clearing the deposit (ensures deposit is included in totalPrincipal)
        uint256 yieldAmount = _calculateYield(principalAmount);
        
        _clearDeposit(user, depositNonce);
        (uint256 actualPrincipal, uint256 actualYield) = _withdrawAndDistribute(merchantPayout, principalAmount, yieldAmount, merchantPayout);
        
        emit DepositReleased(user, merchantPayout, actualPrincipal, actualYield, depositNonce);
    }

    /// @notice Refund principal to user (merchant or arbiter can call)
    /// @param user The user address whose deposit should be refunded
    /// @param depositNonce The nonce of the deposit to refund
    function refund(address user, uint256 depositNonce) 
        external 
        onlyMerchantOrArbiter(deposits[user][depositNonce].merchantPayout)
    {
        Deposit memory deposit = deposits[user][depositNonce];
        require(deposit.principal > 0, "No deposit");
        require(deposit.merchantPayout != address(0), "No merchant payout");
        
        uint256 principalAmount = deposit.principal;
        
        // Calculate yield BEFORE clearing the deposit (ensures deposit is included in totalPrincipal)
        uint256 yieldAmount = _calculateYield(principalAmount);
        
        _clearDeposit(user, depositNonce);
        (uint256 actualPrincipal, uint256 actualYield) = _withdrawAndDistribute(user, principalAmount, yieldAmount, deposit.merchantPayout);
        
        emit DepositRefunded(user, msg.sender, actualPrincipal, actualYield, depositNonce);
    }
}
