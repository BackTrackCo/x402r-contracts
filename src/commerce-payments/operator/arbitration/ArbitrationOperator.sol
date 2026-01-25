// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperatorAccess} from "./ArbitrationOperatorAccess.sol";
import {ZeroAddress, ZeroAmount} from "../../types/Errors.sol";
import {ZeroEscrow, ZeroArbiter} from "../types/Errors.sol";
import {
    TotalFeeRateExceedsMax,
    InvalidAuthorizationExpiry,
    InvalidFeeBps,
    InvalidFeeReceiver,
    ETHTransferFailed,
    ConditionNotMet
} from "../types/Errors.sol";
import {IOperator} from "../types/IOperator.sol";
import {ICondition} from "../../conditions/ICondition.sol";
import {IRecorder} from "../../conditions/IRecorder.sol";
import {PaymentState} from "../types/Types.sol";
import {
    AuthorizationCreated,
    ChargeExecuted,
    ReleaseExecuted,
    RefundExecuted,
    ProtocolFeesEnabledUpdated,
    FeesDistributed
} from "../types/Events.sol";

/**
 * @title ArbitrationOperator
 * @notice Operator contract for x402r - condition-based escrow release for Chamba universal execution protocol.
 *         Anyone (agents, robots, humans) can post jobs, anyone can execute them, payment held in escrow
 *         until verification via release condition contract.
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
 * ARCHITECTURE: Implements IOperator. Users call operator methods directly:
 *        User -> operator.authorize() -> escrow.authorize()
 *        User -> operator.charge() -> escrow.charge()
 *        User -> operator.release() -> escrow.capture()
 */
contract ArbitrationOperator is Ownable, ArbitrationOperatorAccess, IOperator {
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
    address public immutable ARBITER;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public paymentInfos;

    // Payment indexing for discoverability
    mapping(address => bytes32[]) private payerPayments;
    mapping(address => bytes32[]) private receiverPayments;

    // ============ Fee Configuration ============
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;
    uint256 public immutable MAX_ARBITER_FEE_RATE;

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

    address public immutable protocolFeeRecipient;
    bool public feesEnabled;

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage,
        address _arbiter,
        address _owner,
        ConditionConfig memory _conditions
    ) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_arbiter == address(0)) revert ZeroArbiter();
        ESCROW = AuthCaptureEscrow(_escrow);
        ARBITER = _arbiter;
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        _initializeOwner(_owner);
        if (_maxTotalFeeRate == 0) revert ZeroAmount();
        if (_protocolFeePercentage > 100) revert TotalFeeRateExceedsMax();

        protocolFeeRecipient = _protocolFeeRecipient;
        feesEnabled = false;

        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
        MAX_ARBITER_FEE_RATE = (_maxTotalFeeRate * (100 - _protocolFeePercentage)) / 100;

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
     * @dev Checks AUTHORIZE_CONDITION, performs authorization, then calls AUTHORIZE_RECORDER
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - authorizationExpiry == type(uint48).max
     *        - minFeeBps == maxFeeBps == MAX_TOTAL_FEE_RATE
     *        - feeReceiver == address(this)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validOperator(paymentInfo) validFees(paymentInfo, MAX_TOTAL_FEE_RATE) {
        // ============ CHECKS ============
        // Check AUTHORIZE_CONDITION (address(0) = always allow)
        if (address(AUTHORIZE_CONDITION) != address(0)) {
            if (!AUTHORIZE_CONDITION.check(paymentInfo, msg.sender)) {
                revert ConditionNotMet();
            }
        }
        if (paymentInfo.authorizationExpiry != type(uint48).max) revert InvalidAuthorizationExpiry();

        // ============ EFFECTS ============
        // Compute hash and update state before external call (CEI pattern)
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        paymentInfos[paymentInfoHash] = paymentInfo;
        _addPayerPayment(paymentInfo.payer, paymentInfoHash);
        _addReceiverPayment(paymentInfo.receiver, paymentInfoHash);

        // ============ INTERACTIONS ============
        ESCROW.authorize(paymentInfo, amount, tokenCollector, collectorData);

        // Call AUTHORIZE_RECORDER (address(0) = no-op)
        if (address(AUTHORIZE_RECORDER) != address(0)) {
            AUTHORIZE_RECORDER.record(paymentInfo, amount, msg.sender);
        }

        emit AuthorizationCreated(paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount, block.timestamp);
    }

    /**
     * @notice Direct charge - collects payment and immediately transfers to receiver
     * @dev Checks CHARGE_CONDITION, performs charge, then calls CHARGE_RECORDER.
     *      Unlike authorize(), funds go directly to receiver (no escrow hold).
     *      Refunds are only possible via refundPostEscrow().
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - minFeeBps == maxFeeBps == MAX_TOTAL_FEE_RATE
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
    ) external validOperator(paymentInfo) validFees(paymentInfo, MAX_TOTAL_FEE_RATE) {
        // ============ CHECKS ============
        // Check CHARGE_CONDITION (address(0) = always allow)
        if (address(CHARGE_CONDITION) != address(0)) {
            if (!CHARGE_CONDITION.check(paymentInfo, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // ============ EFFECTS ============
        // Compute hash and update state before external call (CEI pattern)
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        paymentInfos[paymentInfoHash] = paymentInfo;
        _addPayerPayment(paymentInfo.payer, paymentInfoHash);
        _addReceiverPayment(paymentInfo.receiver, paymentInfoHash);

        // ============ INTERACTIONS ============
        ESCROW.charge(paymentInfo, amount, tokenCollector, collectorData, feeBps, feeReceiver);

        // Call CHARGE_RECORDER (address(0) = no-op)
        if (address(CHARGE_RECORDER) != address(0)) {
            CHARGE_RECORDER.record(paymentInfo, amount, msg.sender);
        }

        emit ChargeExecuted(paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount, block.timestamp);
    }

    /**
     * @notice Release funds to receiver
     * @dev Checks RELEASE_CONDITION, performs capture, then calls RELEASE_RECORDER
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount)
        external
        validOperator(paymentInfo)
    {
        // ============ CHECKS ============
        // Check RELEASE_CONDITION (address(0) = always allow)
        if (address(RELEASE_CONDITION) != address(0)) {
            if (!RELEASE_CONDITION.check(paymentInfo, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit ReleaseExecuted(paymentInfo, amount, block.timestamp);

        // ============ INTERACTIONS ============
        // Forward to escrow - escrow validates payment exists
        ESCROW.capture(paymentInfo, amount, feeBps, feeReceiver);

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
        validOperator(paymentInfo)
    {
        // ============ CHECKS ============
        // Check REFUND_IN_ESCROW_CONDITION (address(0) = always allow)
        if (address(REFUND_IN_ESCROW_CONDITION) != address(0)) {
            if (!REFUND_IN_ESCROW_CONDITION.check(paymentInfo, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit RefundExecuted(paymentInfo, paymentInfo.payer, amount);

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
    ) external validOperator(paymentInfo) {
        // ============ CHECKS ============
        // Check REFUND_POST_ESCROW_CONDITION (address(0) = always allow)
        if (address(REFUND_POST_ESCROW_CONDITION) != address(0)) {
            if (!REFUND_POST_ESCROW_CONDITION.check(paymentInfo, msg.sender)) {
                revert ConditionNotMet();
            }
        }

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit RefundExecuted(paymentInfo, paymentInfo.payer, uint120(amount));

        // ============ INTERACTIONS ============
        // Forward to escrow's refund - token collector enforces permission
        ESCROW.refund(paymentInfo, amount, tokenCollector, collectorData);

        // Call REFUND_POST_ESCROW_RECORDER (address(0) = no-op)
        if (address(REFUND_POST_ESCROW_RECORDER) != address(0)) {
            REFUND_POST_ESCROW_RECORDER.record(paymentInfo, amount, msg.sender);
        }
    }

    /**
     * @notice Distribute collected fees to protocol and arbiter
     * @param token The token address to distribute fees for
     */
    function distributeFees(address token) external {
        // ============ CHECKS ============
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance == 0) return;

        uint256 protocolAmount = 0;
        uint256 arbiterAmount = 0;

        if (feesEnabled) {
            protocolAmount = (balance * PROTOCOL_FEE_PERCENTAGE) / 100;
            arbiterAmount = balance - protocolAmount;
        } else {
            arbiterAmount = balance;
        }

        // ============ EFFECTS ============
        // Emit event before external calls (CEI pattern)
        emit FeesDistributed(token, protocolAmount, arbiterAmount);

        // ============ INTERACTIONS ============
        if (protocolAmount > 0) {
            SafeTransferLib.safeTransfer(token, protocolFeeRecipient, protocolAmount);
        }

        if (arbiterAmount > 0) {
            SafeTransferLib.safeTransfer(token, ARBITER, arbiterAmount);
        }
    }

    /// @notice Rescue any ETH accidentally sent to this contract
    /// @dev Solady's Ownable has payable functions; this allows recovery of any stuck ETH
    function rescueETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = msg.sender.call{value: balance}("");
            if (!success) revert ETHTransferFailed();
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

    /**
     * @notice Get all payment hashes for a payer
     * @param payer The payer address
     * @return Array of payment info hashes
     */
    function getPayerPayments(address payer) external view returns (bytes32[] memory) {
        return payerPayments[payer];
    }

    /**
     * @notice Get all payment hashes for a receiver (merchant)
     * @param receiver The receiver address
     * @return Array of payment info hashes
     */
    function getReceiverPayments(address receiver) external view returns (bytes32[] memory) {
        return receiverPayments[receiver];
    }

    // ============ Internal Helpers ============

    /**
     * @notice Add payment hash to payer's list
     * @param payer The payer address
     * @param hash The payment info hash
     */
    function _addPayerPayment(address payer, bytes32 hash) internal {
        payerPayments[payer].push(hash);
    }

    /**
     * @notice Add payment hash to receiver's list
     * @param receiver The receiver address
     * @param hash The payment info hash
     */
    function _addReceiverPayment(address receiver, bytes32 hash) internal {
        receiverPayments[receiver].push(hash);
    }
}
