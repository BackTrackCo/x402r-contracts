// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.33 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ArbiterationOperatorAccess} from "./ArbiterationOperatorAccess.sol";

// Interfaces for Base Commerce Payments
interface IAuthCaptureEscrow {
    function authorize(
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint256 expiry,
        address feeRecipient,
        uint256 feeRate,
        bytes calldata collectorData
    ) external returns (bytes32 authorizationId);
    
    function capture(
        bytes32 authorizationId,
        uint256 amount
    ) external;
    
    function refund(
        bytes32 authorizationId,
        address recipient,
        uint256 amount
    ) external;
    
    function void(bytes32 authorizationId) external;
}

/**
 * @title ArbiterationOperator
 * @notice Operator contract that wraps Base Commerce Payments and enforces
 *         refund delay for uncaptured funds, arbiter refund restrictions, and fee distribution
 */
contract ArbiterationOperator is ArbiterationOperatorAccess, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Base Commerce Payments contracts
    IAuthCaptureEscrow public immutable ESCROW;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points
    
    // Fee configuration (set at deployment)
    uint256 public immutable MAX_TOTAL_FEE_RATE; // Maximum total fee rate in basis points
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE; // Protocol gets X% of total fee (in percentage, not basis points)
    uint256 public immutable MAX_ARBITER_FEE_RATE; // Maximum arbiter fee rate in basis points (auto-calculated as remainder after protocol fee)
    
    // Fee configuration
    address public protocolFeeRecipient;
    bool public feesEnabled;
    
    // Authorization metadata
    struct AuthorizationData {
        address payer;              // Original payer address
        address merchant;            // Merchant address
        address arbiter;             // Arbiter address for this merchant
        address token;               // Token address
        uint256 amount;              // Authorization amount
        uint256 timestamp;           // Authorization timestamp
        bytes32 authorizationId;     // Base Commerce Payments authorization ID
        bool captured;               // Whether funds have been captured
        uint256 capturedAmount;      // Amount captured (if any)
        uint256 refundedAmount;      // Amount refunded (supports partial refunds)
        uint256 refundDelay;         // Escrow time for this authorization (from merchant config at time of creation)
    }
    
    // authorizationId => AuthorizationData
    mapping(bytes32 => AuthorizationData) public authorizations;
    
    // Merchant configuration
    struct MerchantConfig {
        address arbiter;             // Arbiter address (also receives arbiter fees)
        uint256 refundDelay;         // Escrow time - period before merchant can capture funds (set by merchant)
    }
    
    // merchant => MerchantConfig
    mapping(address => MerchantConfig) public merchantConfigs;
    
    // Events
    event AuthorizationCreated(
        bytes32 indexed authorizationId,
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        uint256 timestamp
    );
    
    event CaptureExecuted(
        bytes32 indexed authorizationId,
        uint256 amount,
        uint256 timestamp
    );
    
    event RefundExecuted(
        bytes32 indexed authorizationId,
        address indexed recipient,
        uint256 amount,
        bool wasCaptured
    );
    
    event MerchantRegistered(
        address indexed merchant,
        address indexed arbiter,
        uint256 refundDelay
    );
    
    event MerchantArbiterUpdated(
        address indexed merchant,
        address indexed oldArbiter,
        address indexed newArbiter
    );
    
    event MerchantRefundDelayUpdated(
        address indexed merchant,
        uint256 oldRefundDelay,
        uint256 newRefundDelay
    );
    
    event ProtocolFeesEnabledUpdated(bool enabled);
    
    // Custom errors (gas-efficient alternative to require strings)
    // Note: MerchantNotRegistered, AuthorizationDoesNotExist, NotMerchant, NotArbiter, NotPayer, NotMerchantOrArbiter
    // are inherited from ArbiterationOperatorAccess
    error ZeroAddress();
    error ZeroAmount();
    error AlreadyRegistered();
    error AlreadyCaptured();
    error AlreadyRefunded();
    error NotCaptured();
    error AmountExceedsAuthorization();
    error AmountExceedsAvailable();
    error EscrowTimeNotPassed();
    error TotalFeeRateExceedsMax();
    error InvalidRefundDelay();
    
    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage
    ) Ownable(msg.sender) {
        if (_escrow == address(0)) revert ZeroAddress();
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_maxTotalFeeRate == 0) revert ZeroAmount();
        if (_protocolFeePercentage > 100) revert TotalFeeRateExceedsMax(); // Protocol fee percentage cannot exceed 100%
        
        ESCROW = IAuthCaptureEscrow(_escrow);
        protocolFeeRecipient = _protocolFeeRecipient;
        feesEnabled = false; // Protocol fees disabled by default (arbiters get all fees)
        
        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
        // Calculate arbiter fee rate as remainder after protocol fee: (100 - protocol%) of total fee rate
        MAX_ARBITER_FEE_RATE = (_maxTotalFeeRate * (100 - _protocolFeePercentage)) / 100;
    }
    
    /**
     * @notice Register a merchant with arbiter configuration
     * @dev Arbiter fee rate is always MAX_ARBITER_FEE_RATE (set at deployment)
     *      Arbiter fees are sent directly to the arbiter address
     *      refundDelay: Escrow time set by merchant (must be greater than 0)
     */
    function registerMerchant(
        address merchant,
        address arbiter,
        uint256 refundDelay
    ) external {
        if (merchant == address(0)) revert ZeroAddress();
        if (arbiter == address(0)) revert ZeroAddress();
        if (refundDelay == 0) revert InvalidRefundDelay();
        if (merchantConfigs[merchant].arbiter != address(0)) revert AlreadyRegistered();
        
        merchantConfigs[merchant] = MerchantConfig({
            arbiter: arbiter,
            refundDelay: refundDelay
        });
        
        emit MerchantRegistered(merchant, arbiter, refundDelay);
    }
    
    /**
     * @notice Update merchant's arbiter configuration
     * @dev Only the merchant can update their own arbiter configuration
     *      This allows merchants to change arbiters
     *      Arbiter fee rate is always MAX_ARBITER_FEE_RATE (set at deployment)
     *      Arbiter fees are sent directly to the arbiter address
     */
    function updateMerchantArbiter(
        address arbiter
    ) external {
        address merchant = msg.sender;
        if (merchantConfigs[merchant].arbiter == address(0)) revert MerchantNotRegistered();
        if (arbiter == address(0)) revert ZeroAddress();
        
        MerchantConfig storage config = merchantConfigs[merchant];
        address oldArbiter = config.arbiter;
        
        // Update configuration
        config.arbiter = arbiter;
        
        emit MerchantArbiterUpdated(merchant, oldArbiter, arbiter);
    }
    
    /**
     * @notice Update merchant's escrow time (refund delay)
     * @dev Only the merchant can update their own escrow time
     *      This allows merchants to adjust how long funds stay in escrow before capture
     *      New authorizations will use the updated delay, existing ones use their original delay
     */
    function updateMerchantRefundDelay(
        uint256 refundDelay
    ) external {
        address merchant = msg.sender;
        if (merchantConfigs[merchant].arbiter == address(0)) revert MerchantNotRegistered();
        if (refundDelay == 0) revert InvalidRefundDelay();
        
        MerchantConfig storage config = merchantConfigs[merchant];
        uint256 oldRefundDelay = config.refundDelay;
        config.refundDelay = refundDelay;
        
        emit MerchantRefundDelayUpdated(merchant, oldRefundDelay, refundDelay);
    }
    
    /**
     * @notice Enable or disable protocol fees
     * @dev Only the owner can toggle protocol fees
     *      When disabled, arbiters receive 100% of fees (instead of 75%)
     *      Total fee rate remains the same (0.5 bps), only the split changes
     */
    function setFeesEnabled(bool enabled) external onlyOwner {
        feesEnabled = enabled;
        emit ProtocolFeesEnabledUpdated(enabled);
    }
    
    /**
     * @notice Authorize payment via Base Commerce Payments
     * @dev Wraps Base Commerce Payments authorize() and stores metadata
     *      API matches Base Commerce Payments for compatibility, even if some fields are not used
     *      expiry: Set to max (type(uint256).max) to keep funds available for refunds indefinitely
     *      collectorData: Passed through but not used by this operator
     */
    function authorize(
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint256 /* expiry */, // Accepted for API compatibility but overridden to type(uint256).max
        bytes calldata collectorData
    ) external returns (bytes32 authorizationId) {
        if (payer == address(0)) revert ZeroAddress();
        if (merchant == address(0)) revert ZeroAddress();
        if (merchantConfigs[merchant].arbiter == address(0)) revert MerchantNotRegistered();
        if (amount == 0) revert ZeroAmount();
        
        MerchantConfig memory config = merchantConfigs[merchant];
        
        // Use the configured maximum total fee rate
        // The split between protocol and arbiter is determined by PROTOCOL_FEE_PERCENTAGE
        // and feesEnabled flag
        uint256 totalFeeRate = MAX_TOTAL_FEE_RATE;
        
        // Call Base Commerce Payments authorize()
        // NOTE: Setting feeRecipient to address(this) means Base Commerce Payments will send
        // fees to this operator contract when capture() is called. The operator then splits
        // and distributes those fees: if protocol fees enabled, split 25%/75%, otherwise 0%/100%
        // Override expiry to max to ensure funds never expire and remain available for refunds indefinitely
        authorizationId = ESCROW.authorize(
            payer,
            merchant,
            token,
            amount,
            type(uint256).max, // Override expiry to max - keep funds available for refunds indefinitely
            address(this), // Fee recipient (operator contract receives fees, then distributes them)
            totalFeeRate,
            collectorData // Pass through for API compatibility, even if not used
        );
        
        // Store authorization metadata with merchant's escrow time
        authorizations[authorizationId] = AuthorizationData({
            payer: payer,
            merchant: merchant,
            arbiter: config.arbiter,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            authorizationId: authorizationId,
            captured: false,
            capturedAmount: 0,
            refundedAmount: 0,
            refundDelay: config.refundDelay
        });
        
        emit AuthorizationCreated(authorizationId, payer, merchant, amount, block.timestamp);
    }
    
    /**
     * @notice Capture authorized funds
     * @dev Merchant cannot capture until REFUND_DELAY period has passed
     *      This ensures funds remain available for refunds during the delay period
     *      Once captured, merchant has the funds and can use them freely
     */
    function capture(bytes32 authorizationId, uint256 amount) 
        external 
        nonReentrant
        onlyMerchantForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        if (auth.captured) revert AlreadyCaptured();
        if (amount == 0) revert ZeroAmount();
        
        // Calculate available amount for capture (original amount minus already refunded)
        uint256 availableAmount = auth.amount - auth.refundedAmount;
        if (amount > availableAmount) revert AmountExceedsAvailable();
        
        // Enforce escrow time - merchant must wait before capturing
        if (block.timestamp < auth.timestamp + auth.refundDelay) revert EscrowTimeNotPassed();
        
        // Call Base Commerce Payments capture()
        ESCROW.capture(authorizationId, amount);
        
        auth.captured = true;
        auth.capturedAmount = amount;
        
        // Distribute fees after capture
        _distributeFees(authorizationId);
        
        emit CaptureExecuted(authorizationId, amount, block.timestamp);
    }
    
    /**
     * @notice Execute refund (pre-capture)
     * @dev CRITICAL: Arbiter can only refund to original payer
     *      Pre-capture: requires arbiter OR merchant approval
     *      Supports partial refunds - can refund any amount up to the uncaptured amount
     * @param authorizationId The authorization ID to refund
     * @param amount The amount to refund (must be <= uncaptured amount)
     */
    function refundInEscrow(bytes32 authorizationId, uint256 amount) 
        external 
        nonReentrant
        onlyMerchantOrArbiterForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        if (auth.captured) revert AlreadyCaptured();
        if (amount == 0) revert ZeroAmount();
        
        // Calculate available amount for refund (original amount minus already refunded)
        uint256 availableAmount = auth.amount - auth.refundedAmount;
        if (amount > availableAmount) revert AmountExceedsAvailable();
        
        // CRITICAL: Arbiter can only refund to original payer
        // This is enforced by the access control - arbiter can only call if they're the arbiter
        // And we're always refunding to auth.payer (the original payer)
        
        // Update state before external call (checks-effects-interactions pattern)
        auth.refundedAmount += amount;
        
        // Call Base Commerce Payments refund()
        ESCROW.refund(authorizationId, auth.payer, amount);
        
        emit RefundExecuted(authorizationId, auth.payer, amount, false);
    }
    
    /**
     * @notice Execute refund (post-capture)
     * @dev Post-capture: requires merchant approval only
     *      Supports partial refunds - can refund any amount up to the captured amount
     * @param authorizationId The authorization ID to refund
     * @param amount The amount to refund (must be <= captured amount minus already refunded)
     */
    function refundPostEscrow(bytes32 authorizationId, uint256 amount) 
        external 
        nonReentrant
        onlyMerchantForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        if (!auth.captured) revert NotCaptured();
        if (amount == 0) revert ZeroAmount();
        
        // Calculate available amount for refund (captured amount minus already refunded)
        uint256 availableAmount = auth.capturedAmount - auth.refundedAmount;
        if (amount > availableAmount) revert AmountExceedsAvailable();
        
        // Update state before external call (checks-effects-interactions pattern)
        auth.refundedAmount += amount;
        
        // Call Base Commerce Payments refund()
        ESCROW.refund(authorizationId, auth.payer, amount);
        
        emit RefundExecuted(authorizationId, auth.payer, amount, true);
    }
    
    /**
     * @notice Distribute fees after capture
     * @dev Base Commerce Payments sends fees to this contract (feeRecipient) when capture() is called.
     *      This function splits and distributes those fees to protocol and arbiter recipients.
     *      Note: This assumes fees are sent to this contract. If Base Commerce Payments handles
     *      fee distribution differently, this logic may need adjustment.
     */
    function _distributeFees(bytes32 authorizationId) internal {
        AuthorizationData memory auth = authorizations[authorizationId];
        MerchantConfig memory config = merchantConfigs[auth.merchant];
        
        // Calculate total fees based on captured amount and configured total fee rate
        uint256 totalFee = (auth.capturedAmount * MAX_TOTAL_FEE_RATE) / BASIS_POINTS;
        
        // Split fees based on protocol fee switch
        // If protocol fees enabled: protocol gets PROTOCOL_FEE_PERCENTAGE%, arbiter gets remainder
        // If protocol fees disabled: protocol gets 0%, arbiter gets 100%
        uint256 protocolFee = 0;
        uint256 arbiterFee = totalFee;
        
        if (feesEnabled) {
            protocolFee = (totalFee * PROTOCOL_FEE_PERCENTAGE) / 100;
            arbiterFee = totalFee - protocolFee;
        }
        
        // Transfer protocol fee (if any)
        if (protocolFee > 0) {
            IERC20(auth.token).safeTransfer(protocolFeeRecipient, protocolFee);
        }
        
        // Transfer arbiter fee (always gets remainder, which is 100% when protocol fees disabled)
        if (arbiterFee > 0) {
            IERC20(auth.token).safeTransfer(config.arbiter, arbiterFee);
        }
    }
    
    /**
     * @notice Void an authorization (cancel before capture)
     * @dev Payer CANNOT void - they received the item instantly, so they must stay in escrow
     *      Only merchant or arbiter can void (e.g., if there's an error before capture)
     */
    function void(bytes32 authorizationId) 
        external 
        onlyMerchantOrArbiterForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        if (auth.captured) revert AlreadyCaptured();
        if (auth.refundedAmount > 0) revert AlreadyRefunded();
        
        ESCROW.void(authorizationId);
    }
    
    
    /**
     * @notice Check if authorization is captured
     * @param authorizationId The authorization ID
     * @return captured Whether the authorization is captured
     */
    function isCaptured(bytes32 authorizationId)
        external
        view
        returns (bool captured)
    {
        AuthorizationData memory auth = authorizations[authorizationId];
        if (auth.payer == address(0)) revert ZeroAddress();
        return auth.captured;
    }
    
    /**
     * @notice Get authorization data
     */
    function getAuthorization(bytes32 authorizationId)
        external
        view
        returns (AuthorizationData memory auth)
    {
        auth = authorizations[authorizationId];
        if (auth.payer == address(0)) revert ZeroAddress();
    }
    
    /**
     * @notice Get payer address for an authorization
     * @param authorizationId The authorization ID
     * @return payer The payer address
     */
    function getPayer(bytes32 authorizationId)
        external
        view
        returns (address payer)
    {
        AuthorizationData memory auth = authorizations[authorizationId];
        if (auth.payer == address(0)) revert ZeroAddress();
        return auth.payer;
    }
    
    // Implementation of ArbiterationOperatorAccess abstract functions
    
    /**
     * @notice Get arbiter for a merchant
     * @param merchant The merchant address
     * @return The arbiter address
     */
    function getArbiter(address merchant) public view override returns (address) {
        return merchantConfigs[merchant].arbiter;
    }
    
    /**
     * @notice Check if merchant is registered
     * @param merchant The merchant address
     * @return Whether the merchant is registered
     */
    function isMerchantRegistered(address merchant) public view override returns (bool) {
        return merchantConfigs[merchant].arbiter != address(0);
    }
    
    /**
     * @notice Get merchant for an authorization (internal helper for modifiers)
     * @param authorizationId The authorization ID
     * @return The merchant address
     */
    function _getMerchantForAuthorization(bytes32 authorizationId) 
        internal 
        view 
        override 
        returns (address) 
    {
        AuthorizationData memory auth = authorizations[authorizationId];
        return auth.merchant;
    }
    
    // Public helper functions for external contracts (e.g., RefundRequest)
    
    /**
     * @notice Check if caller is merchant for an authorization
     * @param authorizationId The authorization ID
     * @param caller The address to check
     * @return True if caller is the merchant for this authorization
     */
    function isMerchantForAuthorization(bytes32 authorizationId, address caller) 
        external 
        view 
        returns (bool) 
    {
        address merchant = _getMerchantForAuthorization(authorizationId);
        if (merchant == address(0)) return false;
        return caller == merchant && isMerchantRegistered(merchant);
    }
    
    /**
     * @notice Check if caller is merchant or arbiter for an authorization
     * @param authorizationId The authorization ID
     * @param caller The address to check
     * @return True if caller is the merchant or arbiter for this authorization
     */
    function isMerchantOrArbiterForAuthorization(bytes32 authorizationId, address caller) 
        external 
        view 
        returns (bool) 
    {
        address merchant = _getMerchantForAuthorization(authorizationId);
        if (merchant == address(0)) return false;
        if (!isMerchantRegistered(merchant)) return false;
        address arbiter = getArbiter(merchant);
        return caller == merchant || caller == arbiter;
    }
    
    /**
     * @notice Get merchant for an authorization (public helper for external contracts)
     * @param authorizationId The authorization ID
     * @return The merchant address
     */
    function getMerchantForAuthorization(bytes32 authorizationId) 
        external 
        view 
        returns (address) 
    {
        return _getMerchantForAuthorization(authorizationId);
    }
}

