// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperatorAccess} from "./ArbitrationOperatorAccess.sol";
import {
    ZeroAddress,
    ZeroAmount,
    RefundPeriodNotPassed,
    TotalFeeRateExceedsMax
} from "../Errors.sol";
import {
    AuthorizationCreated,
    ReleaseExecuted,
    EarlyReleaseExecuted,
    RefundExecuted,
    ProtocolFeesEnabledUpdated,
    FeesDistributed
} from "../Events.sol";

/**
 * @title ArbitrationOperator
 * @notice Operator contract that wraps Base Commerce Payments escrow with arbiter-based dispute resolution.
 *         Uses the exact same PaymentInfo-based interface as AuthCaptureEscrow for x402-escrow compatibility.
 *
 * @dev Key features:
 *      - Immutable arbiter config baked in at deployment
 *      - Immutable refund period baked in at deployment (merchant can only capture after this period)
 *      - Arbiter OR merchant can trigger partial pre-capture refunds via partialVoid
 *      - Uses PaymentInfo struct from Base Commerce Payments for full x402-escrow compatibility
 */
contract ArbitrationOperator is Ownable, ArbitrationOperatorAccess {
    using SafeERC20 for IERC20;

    // Fee configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;
    uint256 public immutable MAX_ARBITER_FEE_RATE;

    // Refund period configuration (set at deployment)
    uint48 public immutable REFUND_PERIOD;

    // Track when each payment was authorized (for refund period calculation)
    mapping(bytes32 => uint48) public authorizationTimestamps;

    address public protocolFeeRecipient;
    bool public feesEnabled;

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage,
        address _arbiter,
        address _owner,
        uint48 _refundPeriod
    ) Ownable(_owner) ArbitrationOperatorAccess(_escrow, _arbiter) {
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_maxTotalFeeRate == 0) revert ZeroAmount();
        if (_protocolFeePercentage > 100) revert TotalFeeRateExceedsMax();
        if (_refundPeriod == 0) revert ZeroAmount();

        protocolFeeRecipient = _protocolFeeRecipient;
        feesEnabled = false;

        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
        MAX_ARBITER_FEE_RATE = (_maxTotalFeeRate * (100 - _protocolFeePercentage)) / 100;
        REFUND_PERIOD = _refundPeriod;
    }

    // ============ Owner Functions ============

    /**
     * @notice Enable or disable protocol fees
     */
    function setFeesEnabled(bool enabled) external onlyOwner {
        feesEnabled = enabled;
        emit ProtocolFeesEnabledUpdated(enabled);
    }

    // ============ Payment Functions ============

    /**
     * @notice Authorize payment via Base Commerce Payments escrow
     * @dev Uses exact same interface as AuthCaptureEscrow.authorize()
     *      The refund period is set at operator deployment, not per-payment.
     * @param paymentInfo PaymentInfo struct (must have operator == address(this))
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validOperator(paymentInfo) {
        // Enforce specific parameters for arbitration model
        AuthCaptureEscrow.PaymentInfo memory enforcedPaymentInfo = paymentInfo;
        enforcedPaymentInfo.authorizationExpiry = type(uint48).max;
        enforcedPaymentInfo.refundExpiry = type(uint48).max; // Satisfies base escrow validation

        // Always use MAX_TOTAL_FEE_RATE
        enforcedPaymentInfo.minFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        enforcedPaymentInfo.maxFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        enforcedPaymentInfo.feeReceiver = address(this);

        // Forward to escrow with enforced parameters
        ESCROW.authorize(enforcedPaymentInfo, amount, tokenCollector, collectorData);

        // Store PaymentInfo for hash-based lookups
        bytes32 paymentInfoHash = ESCROW.getHash(enforcedPaymentInfo);
        paymentInfos[paymentInfoHash] = enforcedPaymentInfo;

        // Store authorization timestamp for refund period calculation
        authorizationTimestamps[paymentInfoHash] = uint48(block.timestamp);

        emit AuthorizationCreated(
            paymentInfoHash,
            enforcedPaymentInfo.payer,
            enforcedPaymentInfo.receiver,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Capture authorized funds after refund period
     * @dev Only receiver can capture, and only after REFUND_PERIOD has passed since authorization
     * @param paymentInfoHash Hash of the PaymentInfo struct
     * @param amount Amount to capture
     */
    function release(
        bytes32 paymentInfoHash,
        uint256 amount
    ) external paymentMustExist(paymentInfoHash) onlyReceiverByHash(paymentInfoHash) validOperatorByHash(paymentInfoHash) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = paymentInfos[paymentInfoHash];

        // Enforce refund period from authorization time
        uint48 authTime = authorizationTimestamps[paymentInfoHash];
        if (block.timestamp < authTime + REFUND_PERIOD) revert RefundPeriodNotPassed();

        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // Forward to escrow
        ESCROW.capture(paymentInfo, amount, feeBps, feeReceiver);

        emit ReleaseExecuted(paymentInfoHash, amount, block.timestamp);
    }

    /**
     * @notice Payer releases funds to receiver early (bypassing refund period)
     * @dev Only payer can call. Bypasses REFUND_PERIOD check.
     * @param paymentInfoHash Hash of the PaymentInfo struct
     * @param amount Amount to release
     */
    function earlyRelease(
        bytes32 paymentInfoHash,
        uint256 amount
    ) external paymentMustExist(paymentInfoHash) onlyPayerByHash(paymentInfoHash) validOperatorByHash(paymentInfoHash) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = paymentInfos[paymentInfoHash];

        // No refund period check for payer early release

        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // Forward to capture
        ESCROW.capture(paymentInfo, amount, feeBps, feeReceiver);

        emit EarlyReleaseExecuted(
            paymentInfoHash,
            paymentInfo.receiver,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Refund funds while still in escrow (before capture)
     * @dev Only arbiter OR receiver can call. Returns escrowed funds to payer.
     * @param paymentInfoHash Hash of the PaymentInfo struct
     * @param amount Amount to return to payer
     */
    function refund(
        bytes32 paymentInfoHash,
        uint120 amount
    ) external paymentMustExist(paymentInfoHash) onlyReceiverOrArbiterByHash(paymentInfoHash) validOperatorByHash(paymentInfoHash) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = paymentInfos[paymentInfoHash];

        // Forward to escrow's partialVoid
        ESCROW.partialVoid(paymentInfo, amount);

        emit RefundExecuted(paymentInfoHash, paymentInfo.payer, amount);
    }

    /**
     * @notice Distribute collected fees to protocol and arbiter
     * @param token The token address to distribute fees for
     */
    function distributeFees(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) return;

        uint256 protocolAmount = 0;
        uint256 arbiterAmount = 0;

        if (feesEnabled) {
            protocolAmount = (balance * PROTOCOL_FEE_PERCENTAGE) / 100;
            arbiterAmount = balance - protocolAmount;
        } else {
            arbiterAmount = balance;
        }

        if (protocolAmount > 0) {
            IERC20(token).safeTransfer(protocolFeeRecipient, protocolAmount);
        }

        if (arbiterAmount > 0) {
            IERC20(token).safeTransfer(ARBITER, arbiterAmount);
        }

        emit FeesDistributed(token, protocolAmount, arbiterAmount);
    }


}
