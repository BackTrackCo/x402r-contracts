// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {RequestStatus} from "../types/Types.sol";
import {
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending,
    ZeroRefundAmount,
    ApproveAmountExceedsRequest
} from "../types/Errors.sol";
import {RefundRequested, RefundRequestStatusUpdated, RefundRequestCancelled} from "../types/Events.sol";

/**
 * @title RefundRequest
 * @notice Refund request lifecycle with arbiter/receiver-gated approval and atomic refund execution.
 * @dev Approval atomically calls PaymentOperator.refundInEscrow() — one tx, no signatures,
 *      no separate condition contract. The operator's condition tree should use
 *      StaticAddressCondition(address(this)) to gate refundInEscrow access.
 *
 *      State machine:
 *        Pending  -> Approved  (onlyArbiterOrReceiver, approve + refundInEscrow atomic if in escrow)
 *        Approved -> Approved  (onlyArbiterOrReceiver, cumulative top-up)
 *        Pending  -> Denied    (onlyArbiter)
 *        Pending  -> Refused   (onlyArbiter)
 *        Pending  -> Cancelled (onlyPayer)
 *
 * SECURITY: ReentrancyGuardTransient protects approve() which makes an external call
 *           to operator.refundInEscrow() after updating state (CEI pattern with defense-in-depth).
 */
contract RefundRequest is ReentrancyGuardTransient {
    /// @notice The arbiter address that can approve, deny, and refuse refund requests
    address public immutable ARBITER;

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

    // ============ Storage ============

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

    // ============ Modifiers ============

    modifier onlyArbiter() {
        _checkOnlyArbiter();
        _;
    }

    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        _checkOnlyPayer(paymentInfo);
        _;
    }

    modifier onlyArbiterOrReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        _checkOnlyArbiterOrReceiver(paymentInfo);
        _;
    }

    modifier operatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        _checkOperatorNotZero(paymentInfo);
        _;
    }

    function _checkOnlyArbiter() internal view {
        if (msg.sender != ARBITER) revert NotArbiter();
    }

    function _checkOnlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
    }

    function _checkOnlyArbiterOrReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view {
        if (msg.sender != ARBITER && msg.sender != paymentInfo.receiver) revert NotArbiterOrReceiver();
    }

    function _checkOperatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal pure {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
    }

    constructor(address _arbiter) {
        if (_arbiter == address(0)) revert ZeroArbiter();
        ARBITER = _arbiter;
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

    /// @notice Approve a refund and atomically execute if funds are in escrow.
    ///         Both arbiter and receiver can call. Approvals are cumulative — each call
    ///         adds `amount` to the running `approvedAmount`. The total cannot exceed
    ///         the requested amount.
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    /// @param amount Additional refund amount to approve (added to previous approvals)
    function approve(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, uint120 amount)
        external
        nonReentrant
        operatorNotZero(paymentInfo)
        onlyArbiterOrReceiver(paymentInfo)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        // CHECKS
        RefundRequestData storage request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending && request.status != RequestStatus.Approved) {
            revert RequestNotPending();
        }
        if (amount == 0) revert ZeroRefundAmount();
        if (request.approvedAmount + amount > request.amount) revert ApproveAmountExceedsRequest();

        // EFFECTS
        RequestStatus previousStatus = request.status;
        request.approvedAmount += amount;
        request.status = RequestStatus.Approved;

        emit RefundRequestStatusUpdated(
            paymentInfo, previousStatus, RequestStatus.Approved, msg.sender, nonce, request.approvedAmount
        );

        // INTERACTIONS — atomic refund execution if funds are still in escrow
        AuthCaptureEscrow escrow = operator.ESCROW();
        (, uint120 capturableAmount,) = escrow.paymentState(paymentInfoHash);
        if (amount <= capturableAmount) {
            operator.refundInEscrow(paymentInfo, amount);
        }
    }

    // ============ Arbiter Actions (msg.sender) ============

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

    function _addPayerRequest(address payer, bytes32 key) internal {
        if (payerRefundRequestExists[payer][key]) return;
        payerRefundRequestExists[payer][key] = true;
        payerRefundRequests[payer][payerRefundRequestCount[payer]] = key;
        payerRefundRequestCount[payer]++;
    }

    function _addReceiverRequest(address receiver, bytes32 key) internal {
        if (receiverRefundRequestExists[receiver][key]) return;
        receiverRefundRequestExists[receiver][key] = true;
        receiverRefundRequests[receiver][receiverRefundRequestCount[receiver]] = key;
        receiverRefundRequestCount[receiver]++;
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

    function getReceiverRefundRequests(address receiver, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = receiverRefundRequestCount[receiver];
        if (offset >= total || count == 0) return (new bytes32[](0), total);
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;
        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = receiverRefundRequests[receiver][offset + i];
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

    function getReceiverRefundRequest(address receiver, uint256 index) external view returns (bytes32) {
        if (index >= receiverRefundRequestCount[receiver]) revert IndexOutOfBounds();
        return receiverRefundRequests[receiver][index];
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
