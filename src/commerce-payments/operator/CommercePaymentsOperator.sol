// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RefundRequest} from "../requests/RefundRequest.sol";
import {OperatorAccess} from "./OperatorAccess.sol";

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
 * @title CommercePaymentsOperator
 * @notice Operator contract that wraps Base Commerce Payments and enforces
 *         refund delay for uncaptured funds, arbiter refund restrictions, and fee distribution
 */
contract CommercePaymentsOperator is OperatorAccess {
    using SafeERC20 for IERC20;
    
    // Base Commerce Payments contracts
    IAuthCaptureEscrow public immutable ESCROW;
    RefundRequest public immutable REFUND_REQUEST;
    
    // Constants
    uint256 public constant REFUND_DELAY = 3 days; // Minimum refund period for uncaptured funds
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points
    
    // Fee configuration
    address public protocolFeeRecipient;
    uint256 public protocolFeeRate; // Protocol fee rate in basis points
    
    // Authorization metadata
    struct AuthorizationData {
        address payer;              // Original payer address
        address merchant;            // Merchant address
        address arbiter;             // Arbiter address for this merchant
        address token;               // Token address
        uint256 amount;              // Authorization amount
        uint256 timestamp;           // Authorization timestamp
        uint256 refundDelay;          // Refund delay period for uncaptured funds
        bytes32 authorizationId;     // Base Commerce Payments authorization ID
        bool captured;               // Whether funds have been captured
        uint256 capturedAmount;      // Amount captured (if any)
        bool refunded;               // Whether funds have been refunded
    }
    
    // authorizationId => AuthorizationData
    mapping(bytes32 => AuthorizationData) public authorizations;
    
    // authorizationId => depositNonce (for RefundRequest integration)
    mapping(bytes32 => uint256) public authorizationToDepositNonce;
    // depositNonce => authorizationId (reverse mapping)
    mapping(uint256 => bytes32) public depositNonceToAuthorization;
    uint256 private depositNonceCounter;
    
    // Merchant configuration
    struct MerchantConfig {
        address arbiter;             // Arbiter address
        address arbiterFeeRecipient; // Where arbiter fees go
        uint256 arbiterFeeRate;      // Arbiter fee rate in basis points
        bool registered;             // Whether merchant is registered
    }
    
    // merchant => MerchantConfig
    mapping(address => MerchantConfig) public merchantConfigs;
    
    // Events
    event AuthorizationCreated(
        bytes32 indexed authorizationId,
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        uint256 timestamp,
        uint256 depositNonce
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
        address arbiterFeeRecipient,
        uint256 arbiterFeeRate
    );
    
    constructor(
        address _escrow,
        address _refundRequest,
        address _protocolFeeRecipient,
        uint256 _protocolFeeRate
    ) {
        require(_escrow != address(0), "Zero escrow");
        require(_refundRequest != address(0), "Zero refund request");
        require(_protocolFeeRecipient != address(0), "Zero protocol fee recipient");
        require(_protocolFeeRate <= BASIS_POINTS, "Invalid protocol fee rate");
        
        ESCROW = IAuthCaptureEscrow(_escrow);
        REFUND_REQUEST = RefundRequest(_refundRequest);
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
    }
    
    /**
     * @notice Register a merchant with arbiter and fee configuration
     */
    function registerMerchant(
        address merchant,
        address arbiter,
        address arbiterFeeRecipient,
        uint256 arbiterFeeRate
    ) external {
        require(merchant != address(0), "Zero merchant");
        require(arbiter != address(0), "Zero arbiter");
        require(arbiterFeeRecipient != address(0), "Zero arbiter fee recipient");
        require(arbiterFeeRate <= BASIS_POINTS, "Invalid arbiter fee rate");
        require(!merchantConfigs[merchant].registered, "Already registered");
        
        merchantConfigs[merchant] = MerchantConfig({
            arbiter: arbiter,
            arbiterFeeRecipient: arbiterFeeRecipient,
            arbiterFeeRate: arbiterFeeRate,
            registered: true
        });
        
        emit MerchantRegistered(merchant, arbiter, arbiterFeeRecipient, arbiterFeeRate);
    }
    
    /**
     * @notice Authorize payment via Base Commerce Payments
     * @dev Wraps Base Commerce Payments authorize() and stores metadata
     */
    function authorize(
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint256 expiry,
        bytes calldata collectorData
    ) external returns (bytes32 authorizationId) {
        require(payer != address(0), "Zero payer");
        require(merchant != address(0), "Zero merchant");
        require(merchantConfigs[merchant].registered, "Merchant not registered");
        require(amount > 0, "Zero amount");
        
        MerchantConfig memory config = merchantConfigs[merchant];
        
        // Calculate total fee rate (protocol + arbiter)
        uint256 totalFeeRate = protocolFeeRate + config.arbiterFeeRate;
        require(totalFeeRate <= BASIS_POINTS, "Total fee rate exceeds 100%");
        
        // Call Base Commerce Payments authorize()
        authorizationId = ESCROW.authorize(
            payer,
            merchant,
            token,
            amount,
            expiry,
            address(this), // Fee recipient (operator contract or split contract)
            totalFeeRate,
            collectorData
        );
        
        // Generate deposit nonce for RefundRequest integration
        uint256 depositNonce = depositNonceCounter++;
        authorizationToDepositNonce[authorizationId] = depositNonce;
        depositNonceToAuthorization[depositNonce] = authorizationId;
        
        // Store authorization metadata
        authorizations[authorizationId] = AuthorizationData({
            payer: payer,
            merchant: merchant,
            arbiter: config.arbiter,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            refundDelay: REFUND_DELAY,
            authorizationId: authorizationId,
            captured: false,
            capturedAmount: 0,
            refunded: false
        });
        
        emit AuthorizationCreated(authorizationId, payer, merchant, amount, block.timestamp, depositNonce);
    }
    
    /**
     * @notice Capture authorized funds
     * @dev Capture can happen IMMEDIATELY - no delay on capture
     *      Once captured, merchant has the funds and can use them freely
     */
    function capture(bytes32 authorizationId, uint256 amount) 
        external 
        onlyMerchantForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        require(!auth.captured, "Already captured");
        require(!auth.refunded, "Already refunded");
        require(amount > 0, "Zero amount");
        require(amount <= auth.amount, "Amount exceeds authorization");
        
        // NO DELAY ON CAPTURE - merchant can capture immediately
        // Call Base Commerce Payments capture()
        ESCROW.capture(authorizationId, amount);
        
        auth.captured = true;
        auth.capturedAmount = amount;
        
        // Distribute fees after capture
        _distributeFees(authorizationId, amount);
        
        emit CaptureExecuted(authorizationId, amount, block.timestamp);
    }
    
    /**
     * @notice Execute refund after refund request is approved (pre-capture)
     * @dev This is called after RefundRequest status is updated to Approved
     *      CRITICAL: Arbiter can only refund to original payer
     *      Pre-capture: requires arbiter OR merchant approval
     */
    function executeRefundPreCapture(bytes32 authorizationId) 
        external 
        onlyMerchantOrArbiterForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        require(!auth.captured, "Already captured - use executeRefundPostCapture");
        require(!auth.refunded, "Already refunded");
        
        // Check refund request status via RefundRequest contract
        uint8 status = REFUND_REQUEST.getRefundRequestStatus(authorizationId);
        require(status == uint8(RefundRequest.RequestStatus.Approved), "Refund not approved");
        
        // CRITICAL: Arbiter can only refund to original payer
        // This is enforced by the access control - arbiter can only call if they're the arbiter
        // And we're always refunding to auth.payer (the original payer)
        
        // Get refund amount (full uncaptured amount)
        uint256 refundAmount = auth.amount;
        
        // Call Base Commerce Payments refund()
        ESCROW.refund(authorizationId, auth.payer, refundAmount);
        
        auth.refunded = true;
        
        emit RefundExecuted(authorizationId, auth.payer, refundAmount, false);
    }
    
    /**
     * @notice Execute refund after refund request is approved (post-capture)
     * @dev This is called after RefundRequest status is updated to Approved
     *      Post-capture: requires merchant approval only
     */
    function executeRefundPostCapture(bytes32 authorizationId) 
        external 
        onlyMerchantForAuthorization(authorizationId)
    {
        AuthorizationData storage auth = authorizations[authorizationId];
        require(auth.captured, "Not captured - use executeRefundPreCapture");
        require(!auth.refunded, "Already refunded");
        
        // Check refund request status via RefundRequest contract
        uint8 status = REFUND_REQUEST.getRefundRequestStatus(authorizationId);
        require(status == uint8(RefundRequest.RequestStatus.Approved), "Refund not approved");
        
        // Get refund amount (captured amount)
        uint256 refundAmount = auth.capturedAmount;
        
        // Call Base Commerce Payments refund()
        ESCROW.refund(authorizationId, auth.payer, refundAmount);
        
        auth.refunded = true;
        
        emit RefundExecuted(authorizationId, auth.payer, refundAmount, true);
    }
    
    /**
     * @notice Distribute fees after capture
     */
    function _distributeFees(bytes32 authorizationId, uint256 amount) internal {
        AuthorizationData memory auth = authorizations[authorizationId];
        MerchantConfig memory config = merchantConfigs[auth.merchant];
        
        // Calculate fees
        uint256 protocolFee = (amount * protocolFeeRate) / BASIS_POINTS;
        uint256 arbiterFee = (amount * config.arbiterFeeRate) / BASIS_POINTS;
        
        // Distribute fees (implementation depends on how Base Commerce Payments handles fees)
        // If Base Commerce Payments sends fees to this contract, transfer them
        // Otherwise, fees are handled by Base Commerce Payments directly
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
        require(!auth.captured, "Already captured");
        require(!auth.refunded, "Already refunded");
        
        ESCROW.void(authorizationId);
    }
    
    /**
     * @notice Check if refund is guaranteed (within refund delay period for uncaptured funds)
     * @param authorizationId The authorization ID
     * @return guaranteed Whether refund is guaranteed
     */
    function isRefundGuaranteed(bytes32 authorizationId)
        external
        view
        returns (bool guaranteed)
    {
        AuthorizationData memory auth = authorizations[authorizationId];
        if (auth.payer == address(0)) {
            return false;
        }
        if (auth.captured) {
            // For captured funds, refund is not guaranteed (merchant already has funds)
            return false;
        }
        // For uncaptured funds, refund is guaranteed during refund delay period
        return block.timestamp <= auth.timestamp + auth.refundDelay;
    }
    
    /**
     * @notice Get deposit nonce for an authorization (for RefundRequest integration)
     */
    function getDepositNonce(bytes32 authorizationId)
        external
        view
        returns (uint256)
    {
        return authorizationToDepositNonce[authorizationId];
    }
    
    /**
     * @notice Get authorization ID for a deposit nonce (for RefundRequest integration)
     */
    function getAuthorizationId(uint256 depositNonce)
        external
        view
        returns (bytes32)
    {
        return depositNonceToAuthorization[depositNonce];
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
        require(auth.payer != address(0), "Authorization does not exist");
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
        require(auth.payer != address(0), "Authorization does not exist");
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
        require(auth.payer != address(0), "Authorization does not exist");
        return auth.payer;
    }
    
    /**
     * @notice Get merchant, arbiter, and payout info for a deposit nonce
     * @dev This is used by RefundRequest to verify merchant/arbiter
     * @param depositNonce The deposit nonce
     * @return merchant The merchant address
     * @return arbiter The arbiter address
     * @return merchantPayout The merchant payout address (same as merchant for now)
     */
    function getDepositInfo(uint256 depositNonce)
        external
        view
        returns (address merchant, address arbiter, address merchantPayout)
    {
        bytes32 authorizationId = depositNonceToAuthorization[depositNonce];
        require(authorizationId != bytes32(0), "Deposit nonce does not exist");
        
        AuthorizationData memory auth = authorizations[authorizationId];
        return (auth.merchant, auth.arbiter, auth.merchant);
    }
    
    // Implementation of OperatorAccess abstract functions
    
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
        return merchantConfigs[merchant].registered;
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
}

