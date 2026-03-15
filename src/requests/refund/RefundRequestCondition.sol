// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {ICondition} from "../../plugins/conditions/ICondition.sol";
import {RequestStatus} from "../types/Types.sol";
import {
    ApproveAmountExceedsRequest,
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending,
    ZeroRefundAmount
} from "../types/Errors.sol";
import {RefundRequested, RefundRequestStatusUpdated, RefundRequestCancelled} from "../types/Events.sol";

/**
 * @title RefundRequestCondition
 * @notice Refund request lifecycle with msg.sender-gated approval. Implements ICondition
 *         so approval IS the condition state change, enabling permissionless refund execution.
 * @dev One deployment per arbiter (immutable ARBITER). No EIP-712 signatures, no tree walking.
 *
 *      Operator condition tree: OrCondition(ReceiverCondition, RefundRequestCondition)
 *
 *      State machine:
 *        Pending -> Approved   (msg.sender, onlyArbiterOrReceiver)
 *        Pending -> Denied     (msg.sender, onlyArbiter)
 *        Pending -> Refused    (msg.sender, onlyArbiter)
 *        Pending -> Cancelled  (msg.sender, onlyPayer)
 *
 * SECURITY: ReentrancyGuardTransient on approve() is defense-in-depth — no external calls
 *           precede state updates, but the guard prevents future regressions.
 */
contract RefundRequestCondition is ICondition, ReentrancyGuardTransient {
    struct RefundRequestData {
        bytes32 paymentInfoHash;
        uint256 nonce;
        uint120 amount;
        uint120 approvedAmount;
        RequestStatus status;
    }

    // ============ Errors ============

    error IndexOutOfBounds();
    error NotArbiter();
    error NotArbiterOrReceiver();
    error NotPayer();
    error InvalidOperator();
    error ZeroArbiter();

    // ============ Immutables ============

    address public immutable ARBITER;

    // ============ Storage ============

    // Cumulative approved refund amounts per payment
    mapping(bytes32 paymentInfoHash => uint120) public approvedRefundAmounts;

    // compositeKey => refund request
    // compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce))
    mapping(bytes32 => RefundRequestData) private refundRequests;

    // Mapping+counter pattern for gas-efficient indexing (no unbounded arrays)
    mapping(address => mapping(uint256 => bytes32)) private payerRefundRequests;
    mapping(address => uint256) public payerRefundRequestCount;
    mapping(address => mapping(uint256 => bytes32)) private receiverRefundRequests;
    mapping(address => uint256) public receiverRefundRequestCount;
    mapping(address => mapping(uint256 => bytes32)) private operatorRefundRequests;
    mapping(address => uint256) public operatorRefundRequestCount;

    // O(1) existence checks for deduplication
    mapping(address => mapping(bytes32 => bool)) private payerRefundRequestExists;
    mapping(address => mapping(bytes32 => bool)) private receiverRefundRequestExists;
    mapping(address => mapping(bytes32 => bool)) private operatorRefundRequestExists;

    // Reverse lookup: paymentInfoHash => full PaymentInfo
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) private paymentInfoStore;

    // Cancel history
    mapping(bytes32 => uint256) public cancelCount;
    mapping(bytes32 => mapping(uint256 => uint120)) private cancelledAmounts;

    // ============ Constructor ============

    constructor(address _arbiter) {
        if (_arbiter == address(0)) revert ZeroArbiter();
        ARBITER = _arbiter;
    }

    // ============ Modifiers ============

    modifier onlyArbiter() {
        if (msg.sender != ARBITER) revert NotArbiter();
        _;
    }

    modifier onlyArbiterOrReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != ARBITER && msg.sender != paymentInfo.receiver) revert NotArbiterOrReceiver();
        _;
    }

    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    modifier operatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
        _;
    }

    // ============ ICondition ============

    /// @notice Returns true if the requested amount is within the cumulative approved refund amount.
    /// @dev Called by the escrow/operator to check if a refund is allowed.
    function check(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address /* caller */
    )
        external
        view
        override
        returns (bool)
    {
        bytes32 key = PaymentOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo);
        return amount <= approvedRefundAmounts[key];
    }

    // ============ Payer Actions ============

    /// @notice Request a refund. Only payer can call.
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount being requested for refund
    /// @param nonce Record index (from PaymentIndexRecorder) identifying which charge
    function requestRefund(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint120 amount, uint256 nonce)
        external
        operatorNotZero(paymentInfo)
        onlyPayer(paymentInfo)
    {
        if (amount == 0) revert ZeroRefundAmount();

        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[compositeKey];
        if (existingRequest.paymentInfoHash != bytes32(0) && existingRequest.status != RequestStatus.Cancelled) {
            revert RequestAlreadyExists();
        }

        // Store paymentInfo by hash (idempotent — same hash always maps to same data)
        if (paymentInfoStore[paymentInfoHash].operator == address(0)) {
            paymentInfoStore[paymentInfoHash] = paymentInfo;
        }

        // Create or update refund request
        refundRequests[compositeKey] = RefundRequestData({
            paymentInfoHash: paymentInfoHash,
            nonce: nonce,
            amount: amount,
            approvedAmount: 0,
            status: RequestStatus.Pending
        });

        // Update indexing mappings (only add if not already indexed)
        _addPayerRequest(paymentInfo.payer, compositeKey);
        _addReceiverRequest(paymentInfo.receiver, compositeKey);
        _addOperatorRequest(paymentInfo.operator, compositeKey);

        emit RefundRequested(paymentInfo, paymentInfo.payer, paymentInfo.receiver, amount, nonce);
    }

    /// @notice Cancel a pending refund request. Only payer can call.
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    function cancelRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        operatorNotZero(paymentInfo)
        onlyPayer(paymentInfo)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        RefundRequestData storage request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        // Record cancel history before updating status
        uint256 index = cancelCount[compositeKey];
        cancelledAmounts[compositeKey][index] = request.amount;
        cancelCount[compositeKey] = index + 1;

        request.status = RequestStatus.Cancelled;

        emit RefundRequestCancelled(paymentInfo, msg.sender, nonce);
    }

    // ============ Arbiter/Receiver Actions ============

    /// @notice Approve a refund request. Only arbiter or receiver can call.
    ///         Atomically updates the condition state (approvedRefundAmounts) and request status.
    ///         The approved amount may differ from the requested amount (partial approval).
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    /// @param amount Amount to approve (must be > 0 and <= requested amount)
    function approve(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, uint120 amount)
        external
        nonReentrant
        operatorNotZero(paymentInfo)
        onlyArbiterOrReceiver(paymentInfo)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        // ============ CHECKS ============
        RefundRequestData storage request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();
        if (amount == 0) revert ZeroRefundAmount();
        if (amount > request.amount) revert ApproveAmountExceedsRequest();

        // ============ EFFECTS ============
        approvedRefundAmounts[paymentInfoHash] += amount;
        request.approvedAmount = amount;
        request.status = RequestStatus.Approved;

        emit RefundRequestStatusUpdated(
            paymentInfo, RequestStatus.Pending, RequestStatus.Approved, msg.sender, nonce, amount
        );
    }

    // ============ Arbiter-Only Actions ============

    /// @notice Deny a refund request. Only arbiter can call.
    ///         Arbiter reviewed evidence and rejects the refund claim.
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    function deny(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        operatorNotZero(paymentInfo)
        onlyArbiter
    {
        _setStatus(paymentInfo, nonce, RequestStatus.Denied);
    }

    /// @notice Refuse a refund request. Only arbiter can call.
    ///         Arbiter won't consider the request (spam, out of jurisdiction, invalid).
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    function refuse(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        operatorNotZero(paymentInfo)
        onlyArbiter
    {
        _setStatus(paymentInfo, nonce, RequestStatus.Refused);
    }

    // ============ Internal ============

    function _setStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, RequestStatus newStatus)
        internal
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        RefundRequestData storage request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        RequestStatus oldStatus = request.status;
        request.status = newStatus;

        emit RefundRequestStatusUpdated(paymentInfo, oldStatus, newStatus, msg.sender, nonce, 0);
    }

    function _addPayerRequest(address _payer, bytes32 key) internal {
        if (payerRefundRequestExists[_payer][key]) return;
        payerRefundRequestExists[_payer][key] = true;
        payerRefundRequests[_payer][payerRefundRequestCount[_payer]] = key;
        payerRefundRequestCount[_payer]++;
    }

    function _addReceiverRequest(address _receiver, bytes32 key) internal {
        if (receiverRefundRequestExists[_receiver][key]) return;
        receiverRefundRequestExists[_receiver][key] = true;
        receiverRefundRequests[_receiver][receiverRefundRequestCount[_receiver]] = key;
        receiverRefundRequestCount[_receiver]++;
    }

    function _addOperatorRequest(address op, bytes32 key) internal {
        if (operatorRefundRequestExists[op][key]) return;
        operatorRefundRequestExists[op][key] = true;
        operatorRefundRequests[op][operatorRefundRequestCount[op]] = key;
        operatorRefundRequestCount[op]++;
    }

    // ============ View Functions ============

    function getRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        view
        returns (RefundRequestData memory)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));
        RefundRequestData memory request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }

    function hasRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        view
        returns (bool)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));
        return refundRequests[compositeKey].paymentInfoHash != bytes32(0);
    }

    function getRefundRequestStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        view
        returns (RequestStatus)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));
        return refundRequests[compositeKey].status;
    }

    function getRefundRequestByKey(bytes32 compositeKey) external view returns (RefundRequestData memory) {
        RefundRequestData memory request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }

    /// @notice Retrieve the full PaymentInfo for a given hash. Only available after a refund has been requested.
    /// @param paymentInfoHash The hash returned by operator.ESCROW().getHash(paymentInfo)
    function getPaymentInfo(bytes32 paymentInfoHash) external view returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory info = paymentInfoStore[paymentInfoHash];
        if (info.operator == address(0)) revert RequestDoesNotExist();
        return info;
    }

    // ============ Paginated View Functions ============

    function getPayerRefundRequests(address payer, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = payerRefundRequestCount[payer];
        if (offset >= total || count == 0) return (new bytes32[](0), total);
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;
        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = payerRefundRequests[payer][offset + i];
        }
    }

    function getReceiverRefundRequests(address _receiver, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = receiverRefundRequestCount[_receiver];
        if (offset >= total || count == 0) return (new bytes32[](0), total);
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;
        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = receiverRefundRequests[_receiver][offset + i];
        }
    }

    function getOperatorRefundRequests(address op, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = operatorRefundRequestCount[op];
        if (offset >= total || count == 0) return (new bytes32[](0), total);
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;
        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = operatorRefundRequests[op][offset + i];
        }
    }

    function getPayerRefundRequest(address payer, uint256 index) external view returns (bytes32) {
        if (index >= payerRefundRequestCount[payer]) revert IndexOutOfBounds();
        return payerRefundRequests[payer][index];
    }

    function getReceiverRefundRequest(address _receiver, uint256 index) external view returns (bytes32) {
        if (index >= receiverRefundRequestCount[_receiver]) revert IndexOutOfBounds();
        return receiverRefundRequests[_receiver][index];
    }

    function getOperatorRefundRequest(address op, uint256 index) external view returns (bytes32) {
        if (index >= operatorRefundRequestCount[op]) revert IndexOutOfBounds();
        return operatorRefundRequests[op][index];
    }

    // ============ Cancel History View Functions ============

    function getCancelCount(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        view
        returns (uint256)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));
        return cancelCount[compositeKey];
    }

    function getCancelledAmount(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, uint256 cancelIndex)
        external
        view
        returns (uint120)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));
        if (cancelIndex >= cancelCount[compositeKey]) revert IndexOutOfBounds();
        return cancelledAmounts[compositeKey][cancelIndex];
    }
}
