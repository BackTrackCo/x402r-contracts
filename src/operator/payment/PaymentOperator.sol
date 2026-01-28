// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperatorAccess} from "./PaymentOperatorAccess.sol";
import {ZeroAddress} from "../../types/Errors.sol";
import {ZeroEscrow, ConditionNotMet, FeeTooHigh} from "../types/Errors.sol";
import {ICondition} from "../../plugins/conditions/ICondition.sol";
import {IRecorder} from "../../plugins/recorders/IRecorder.sol";
import {PaymentState} from "../types/Types.sol";
import {
    AuthorizationCreated,
    ChargeExecuted,
    ReleaseExecuted,
    RefundInEscrowExecuted,
    RefundPostEscrowExecuted,
    FeesDistributed
} from "../types/Events.sol";
import {IFeeCalculator} from "../../plugins/fees/IFeeCalculator.sol";
import {ProtocolFeeConfig} from "../../plugins/fees/ProtocolFeeConfig.sol";

/**
 * @title PaymentOperator
 * @notice Generic operator contract with pluggable conditions for flexible payment authorization.
 *         Supports marketplace escrow, subscriptions, streaming, grants, and any custom payment flow.
 *
 * @dev Condition Combinator Architecture:
 *      - Operator controls flow, conditions and recorders are composable plugins
 *      - 10 slots: 5 conditions (before checks) + 5 recorders (after state updates)
 *      - address(0) = default behavior (allow for conditions, no-op for recorders)
 *      - Conditions implement ICondition.check() -> returns bool (true = allowed)
 *      - Recorders implement IRecorder.record() -> updates state after action
 *      - Conditions can be composed using combinators (Or, And, Not)
 *
 *      Slots:
 *      - AUTHORIZE_CONDITION / AUTHORIZE_RECORDER
 *      - CHARGE_CONDITION / CHARGE_RECORDER
 *      - RELEASE_CONDITION / RELEASE_RECORDER
 *      - REFUND_IN_ESCROW_CONDITION / REFUND_IN_ESCROW_RECORDER
 *      - REFUND_POST_ESCROW_CONDITION / REFUND_POST_ESCROW_RECORDER
 *
 *      Flow for each action:
 *      User -> operator.action() -> [condition.check()?] -> escrow -> [recorder.record()?]
 *
 * FEE SYSTEM (Modular, Additive):
 *      - Protocol fees come from shared ProtocolFeeConfig (timelocked swappable IFeeCalculator)
 *      - Operator fees come from per-operator IFeeCalculator (set at deploy, immutable)
 *      - totalFee = protocolFee + operatorFee (additive)
 *      - Protocol fees tracked per-token in mapping for accurate distribution
 *      - Fee recipients: protocolFeeRecipient on ProtocolFeeConfig, FEE_RECIPIENT on operator
 *
 * ARCHITECTURE: Users call operator methods directly:
 *        User -> operator.authorize() -> escrow.authorize()
 *        User -> operator.charge() -> escrow.charge()
 *        User -> operator.release() -> escrow.capture()
 */
contract PaymentOperator is ReentrancyGuardTransient, PaymentOperatorAccess {
    /// @notice Configuration struct for condition/recorder slots
    struct ConditionConfig {
        address authorizeCondition;
        address authorizeRecorder;
        address chargeCondition;
        address chargeRecorder;
        address releaseCondition;
        address releaseRecorder;
        address refundInEscrowCondition;
        address refundInEscrowRecorder;
        address refundPostEscrowCondition;
        address refundPostEscrowRecorder;
    }

    // ============ Core State ============
    AuthCaptureEscrow public immutable ESCROW;
    address public immutable FEE_RECIPIENT;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public paymentInfos;

    // ============ Fee Configuration (Modular) ============
    IFeeCalculator public immutable FEE_CALCULATOR;
    ProtocolFeeConfig public immutable PROTOCOL_FEE_CONFIG;
    mapping(address token => uint256) public accumulatedProtocolFees;

    // ============ Condition Slots (before-action checks) ============
    // address(0) = always allow (default behavior)
    ICondition public immutable AUTHORIZE_CONDITION;
    ICondition public immutable CHARGE_CONDITION;
    ICondition public immutable RELEASE_CONDITION;
    ICondition public immutable REFUND_IN_ESCROW_CONDITION;
    ICondition public immutable REFUND_POST_ESCROW_CONDITION;

    // ============ Recorder Slots (after-action state updates) ============
    // address(0) = no-op (default behavior)
    IRecorder public immutable AUTHORIZE_RECORDER;
    IRecorder public immutable CHARGE_RECORDER;
    IRecorder public immutable RELEASE_RECORDER;
    IRecorder public immutable REFUND_IN_ESCROW_RECORDER;
    IRecorder public immutable REFUND_POST_ESCROW_RECORDER;

    constructor(
        address _escrow,
        address _protocolFeeConfig,
        address _feeRecipient,
        address _feeCalculator,
        ConditionConfig memory _conditions
    ) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_protocolFeeConfig == address(0)) revert ZeroAddress();

        ESCROW = AuthCaptureEscrow(_escrow);
        FEE_RECIPIENT = _feeRecipient;
        PROTOCOL_FEE_CONFIG = ProtocolFeeConfig(_protocolFeeConfig);
        FEE_CALCULATOR = IFeeCalculator(_feeCalculator);

        // Set condition slots (address(0) = always allow)
        AUTHORIZE_CONDITION = ICondition(_conditions.authorizeCondition);
        CHARGE_CONDITION = ICondition(_conditions.chargeCondition);
        RELEASE_CONDITION = ICondition(_conditions.releaseCondition);
        REFUND_IN_ESCROW_CONDITION = ICondition(_conditions.refundInEscrowCondition);
        REFUND_POST_ESCROW_CONDITION = ICondition(_conditions.refundPostEscrowCondition);

        // Set recorder slots (address(0) = no-op)
        AUTHORIZE_RECORDER = IRecorder(_conditions.authorizeRecorder);
        CHARGE_RECORDER = IRecorder(_conditions.chargeRecorder);
        RELEASE_RECORDER = IRecorder(_conditions.releaseRecorder);
        REFUND_IN_ESCROW_RECORDER = IRecorder(_conditions.refundInEscrowRecorder);
        REFUND_POST_ESCROW_RECORDER = IRecorder(_conditions.refundPostEscrowRecorder);
    }

    // ============ Internal Fee Calculation ============

    /**
     * @notice Calculate total fee (protocol + operator) for a payment action
     * @param paymentInfo The payment info struct
     * @param amount The payment amount
     * @return totalFeeBps Combined fee in basis points
     * @return protocolFeeAmount Protocol fee in token units (for tracking)
     */
    function _calculateFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount)
        internal
        view
        returns (uint16 totalFeeBps, uint256 protocolFeeAmount)
    {
        // Protocol fee from shared config (returns 0 if calculator is address(0))
        uint256 protocolFeeBps = PROTOCOL_FEE_CONFIG.getProtocolFeeBps(paymentInfo, amount, msg.sender);
        protocolFeeAmount = (amount * protocolFeeBps) / 10000;

        // Operator fee (from calculator, or 0 if no calculator)
        uint256 operatorFeeBps;
        if (address(FEE_CALCULATOR) != address(0)) {
            operatorFeeBps = FEE_CALCULATOR.calculateFee(paymentInfo, amount, msg.sender);
        }

        uint256 combinedFeeBps = protocolFeeBps + operatorFeeBps;
        if (combinedFeeBps > 10000) revert FeeTooHigh();
        totalFeeBps = uint16(combinedFeeBps);
    }

    // ============ Payment Functions ============

    /**
     * @notice Authorize payment via Base Commerce Payments escrow
     * @dev Checks AUTHORIZE_CONDITION, performs authorization, then calls AUTHORIZE_RECORDER
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - feeReceiver == address(this)
     *        authorizationExpiry can be set to any value (use type(uint48).max for no expiry)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant validOperator(paymentInfo) validFees(paymentInfo) {
        // ============ CHECKS ============
        // Check AUTHORIZE_CONDITION (address(0) = always allow)
        if (address(AUTHORIZE_CONDITION) != address(0)) {
            if (!AUTHORIZE_CONDITION.check(paymentInfo, amount, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        // ============ EFFECTS ============
        // Compute hash and update state before external call (CEI pattern)
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        paymentInfos[paymentInfoHash] = paymentInfo;

        // Emit event before external calls (CEI pattern)
        emit AuthorizationCreated(paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount, block.timestamp);

        // ============ INTERACTIONS ============
        ESCROW.authorize(paymentInfo, amount, tokenCollector, collectorData);

        // Call AUTHORIZE_RECORDER (address(0) = no-op)
        if (address(AUTHORIZE_RECORDER) != address(0)) {
            AUTHORIZE_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Direct charge - collects payment and immediately transfers to receiver
     * @dev Checks CHARGE_CONDITION, performs charge, then calls CHARGE_RECORDER.
     *      Unlike authorize(), funds go directly to receiver (no escrow hold).
     *      Refunds are only possible via refundPostEscrow().
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - feeReceiver == address(this)
     * @param amount Amount to charge
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function charge(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant validOperator(paymentInfo) validFees(paymentInfo) {
        // ============ CHECKS ============
        // Check CHARGE_CONDITION (address(0) = always allow)
        if (address(CHARGE_CONDITION) != address(0)) {
            if (!CHARGE_CONDITION.check(paymentInfo, amount, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        (uint16 totalFeeBps, uint256 protocolFeeAmount) = _calculateFees(paymentInfo, amount);
        address feeReceiver = address(this);

        // ============ EFFECTS ============
        // Compute hash and update state before external call (CEI pattern)
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        paymentInfos[paymentInfoHash] = paymentInfo;
        accumulatedProtocolFees[paymentInfo.token] += protocolFeeAmount;

        // Emit event before external calls (CEI pattern)
        emit ChargeExecuted(paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount, block.timestamp);

        // ============ INTERACTIONS ============
        ESCROW.charge(paymentInfo, amount, tokenCollector, collectorData, totalFeeBps, feeReceiver);

        // Call CHARGE_RECORDER (address(0) = no-op)
        if (address(CHARGE_RECORDER) != address(0)) {
            CHARGE_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Release funds to receiver
     * @dev Checks RELEASE_CONDITION, performs capture, then calls RELEASE_RECORDER
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount)
        external
        nonReentrant
        validOperator(paymentInfo)
    {
        // ============ CHECKS ============
        // Check RELEASE_CONDITION (address(0) = always allow)
        if (address(RELEASE_CONDITION) != address(0)) {
            if (!RELEASE_CONDITION.check(paymentInfo, amount, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        (uint16 totalFeeBps, uint256 protocolFeeAmount) = _calculateFees(paymentInfo, amount);
        address feeReceiver = address(this);

        // ============ EFFECTS ============
        accumulatedProtocolFees[paymentInfo.token] += protocolFeeAmount;

        // Emit event before external calls (CEI pattern)
        emit ReleaseExecuted(paymentInfo, amount, block.timestamp);

        // ============ INTERACTIONS ============
        // Forward to escrow - escrow validates payment exists
        ESCROW.capture(paymentInfo, amount, totalFeeBps, feeReceiver);

        // Call RELEASE_RECORDER (address(0) = no-op)
        if (address(RELEASE_RECORDER) != address(0)) {
            RELEASE_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Refund funds while still in escrow (before capture)
     * @dev Checks REFUND_IN_ESCROW_CONDITION, performs partialVoid, then calls REFUND_IN_ESCROW_RECORDER
     *      Typically receiver or arbiter can call (controlled via condition).
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to return to payer
     */
    function refundInEscrow(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint120 amount)
        external
        nonReentrant
        validOperator(paymentInfo)
    {
        // ============ CHECKS ============
        // Check REFUND_IN_ESCROW_CONDITION (address(0) = always allow)
        if (address(REFUND_IN_ESCROW_CONDITION) != address(0)) {
            if (!REFUND_IN_ESCROW_CONDITION.check(paymentInfo, amount, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit RefundInEscrowExecuted(paymentInfo, paymentInfo.payer, amount);

        // ============ INTERACTIONS ============
        // Forward to escrow's partialVoid - escrow validates payment exists
        ESCROW.partialVoid(paymentInfo, amount);

        // Call REFUND_IN_ESCROW_RECORDER (address(0) = no-op)
        if (address(REFUND_IN_ESCROW_RECORDER) != address(0)) {
            REFUND_IN_ESCROW_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Refund captured funds back to payer (after capture/release)
     * @dev Checks REFUND_POST_ESCROW_CONDITION, performs refund, then calls REFUND_POST_ESCROW_RECORDER
     *      Permission is enforced by the token collector (e.g., receiver must have approved it,
     *      or collectorData contains receiver's signature). Anyone can call, but refund only
     *      succeeds if the token collector can source the funds.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to refund to payer
     * @param tokenCollector Address of the token collector that will source the refund
     * @param collectorData Data to pass to the token collector (e.g., signatures)
     */
    function refundPostEscrow(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant validOperator(paymentInfo) {
        // ============ CHECKS ============
        // Check REFUND_POST_ESCROW_CONDITION (address(0) = always allow)
        if (address(REFUND_POST_ESCROW_CONDITION) != address(0)) {
            if (!REFUND_POST_ESCROW_CONDITION.check(paymentInfo, amount, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit RefundPostEscrowExecuted(paymentInfo, paymentInfo.payer, amount);

        // ============ INTERACTIONS ============
        // Forward to escrow's refund - token collector enforces permission
        ESCROW.refund(paymentInfo, amount, tokenCollector, collectorData);

        // Call REFUND_POST_ESCROW_RECORDER (address(0) = no-op)
        if (address(REFUND_POST_ESCROW_RECORDER) != address(0)) {
            REFUND_POST_ESCROW_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Distribute collected fees to protocol and operator
     * @dev Protocol gets tracked accumulated amount, operator gets remainder
     * @param token The token address to distribute fees for
     */
    function distributeFees(address token) external nonReentrant {
        // ============ CHECKS ============
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance == 0) return;

        uint256 protocolShare = accumulatedProtocolFees[token];
        // Cap protocol share to balance (safety: rounding could theoretically exceed)
        if (protocolShare > balance) {
            protocolShare = balance;
        }
        uint256 operatorShare = balance - protocolShare;

        // ============ EFFECTS ============
        accumulatedProtocolFees[token] = 0;

        // Emit event before external calls (CEI pattern)
        emit FeesDistributed(token, protocolShare, operatorShare);

        // ============ INTERACTIONS ============
        if (protocolShare > 0) {
            SafeTransferLib.safeTransfer(token, PROTOCOL_FEE_CONFIG.getProtocolFeeRecipient(), protocolShare);
        }

        if (operatorShare > 0) {
            SafeTransferLib.safeTransfer(token, FEE_RECIPIENT, operatorShare);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check if a payment exists (has been authorized)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment exists
     */
    function paymentExists(bytes32 paymentInfoHash) public view returns (bool) {
        return paymentInfos[paymentInfoHash].payer != address(0);
    }

    /**
     * @notice Get stored PaymentInfo for a given hash
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return The stored PaymentInfo struct
     */
    function getPaymentInfo(bytes32 paymentInfoHash) public view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return paymentInfos[paymentInfoHash];
    }

    /**
     * @notice Check if payment is in escrow (has capturable amount)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment is in escrow
     */
    function isInEscrow(bytes32 paymentInfoHash) public view returns (bool) {
        (, uint120 capturableAmount,) = ESCROW.paymentState(paymentInfoHash);
        return capturableAmount > 0;
    }

    /**
     * @notice Get the explicit state of a payment in its lifecycle
     * @param paymentInfo The PaymentInfo struct
     * @return state The current PaymentState enum value
     * @dev See PaymentState enum for state machine documentation
     *
     *      Escrow struct fields:
     *      - hasCollectedPayment: true if authorize() or charge() was called
     *      - capturableAmount: funds in escrow that can be captured (released)
     *      - refundableAmount: captured funds eligible for refund
     */
    function getPaymentState(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (PaymentState state)
    {
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // Check if payment exists in this operator
        if (paymentInfos[paymentInfoHash].payer == address(0)) {
            return PaymentState.NonExistent;
        }

        // Get escrow state
        (bool hasCollectedPayment, uint120 capturableAmount, uint120 refundableAmount) =
            ESCROW.paymentState(paymentInfoHash);

        // If never collected, shouldn't happen if exists in operator, but handle gracefully
        if (!hasCollectedPayment) {
            return PaymentState.NonExistent;
        }

        // Check if expired (can be reclaimed)
        if (capturableAmount > 0 && block.timestamp >= paymentInfo.authorizationExpiry) {
            return PaymentState.Expired;
        }

        // Determine state based on amounts
        if (capturableAmount > 0) {
            // Funds still in escrow, can be captured or voided
            return PaymentState.InEscrow;
        } else if (refundableAmount > 0) {
            // Funds have been captured/released, still within refund window
            return PaymentState.Released;
        } else {
            // No capturable and no refundable = payment is settled
            // Could be: voided, fully refunded, or refund period expired
            return PaymentState.Settled;
        }
    }
}
