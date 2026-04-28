// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IPostActionHook} from "../../plugins/post-action-hooks/IPostActionHook.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {InvalidOperator, NotPayer} from "../../types/Errors.sol";
import {RequestStatus} from "../types/Types.sol";
import {RequestAlreadyExists, RequestDoesNotExist, RequestNotPending, ZeroRefundAmount} from "../types/Errors.sol";
import {RefundRequested, RefundRequestStatusUpdated, RefundRequestCancelled} from "../types/Events.sol";

/**
 * @title RefundRequest
 * @notice Refund request lifecycle as an IPostActionHook plugin for PaymentOperator.
 * @dev ARBITER is an immutable address for deny/refuse gating. Approval happens via
 *      operator.void() which triggers record() on this contract as the
 *      REFUND_IN_ESCROW_POST_ACTION_HOOK.
 *
 *      State machine:
 *        Pending  -> Approved  (operator calls record() after void)
 *        Approved -> Approved  (cumulative top-up via subsequent record() calls)
 *        Pending  -> Denied    (onlyArbiter)
 *        Pending  -> Refused   (onlyArbiter)
 *        Pending  -> Cancelled (payer only)
 *
 *      Keying: paymentInfoHash only (no nonce). One active request per payment.
 *
 *      record() behavior: Called by operator after refund. No-op if no request exists
 *      or not approvable. Caps approved amount at requested amount. Never reverts on
 *      state mismatches.
 */
contract RefundRequest is IPostActionHook {
    /// @notice The arbiter address that can deny and refuse refund requests
    address public immutable ARBITER;

    struct RefundRequestData {
        bytes32 paymentInfoHash;
        uint120 amount;
        uint120 approvedAmount;
        RequestStatus status;
    }

    // ============ Errors ============

    error IndexOutOfBounds();
    error NotArbiter();
    error ZeroArbiter();

    // ============ Storage ============

    // paymentInfoHash => refund request
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

    function _checkOperatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal pure {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
    }

    constructor(address _arbiter) {
        if (_arbiter == address(0)) revert ZeroArbiter();
        ARBITER = _arbiter;
    }

    // ============ IPostActionHook Implementation ============

    /// @notice Called by PaymentOperator after void succeeds.
    ///         No-op if no request exists or request is not approvable.
    ///         Caps approved amount at requested amount. Never reverts on state mismatches.
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount that was refunded
    /// @param caller The address that called operator.void()
    function run(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller,
        bytes calldata /* data */
    )
        external
    {
        // Only the operator in the paymentInfo can call record()
        if (msg.sender != paymentInfo.operator) return;

        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);

        RefundRequestData storage request = refundRequests[paymentInfoHash];

        // No-op if no request exists
        if (request.paymentInfoHash == bytes32(0)) return;

        // No-op if not approvable
        if (request.status != RequestStatus.Pending && request.status != RequestStatus.Approved) return;

        // Cap amount at remaining requestable amount
        uint120 cappedAmount = uint120(amount);
        uint120 remaining = request.amount - request.approvedAmount;
        if (cappedAmount > remaining) {
            cappedAmount = remaining;
        }
        if (cappedAmount == 0) return;

        // Update state
        RequestStatus previousStatus = request.status;
        request.approvedAmount += cappedAmount;
        request.status = RequestStatus.Approved;

        emit RefundRequestStatusUpdated(
            paymentInfo, previousStatus, RequestStatus.Approved, caller, request.approvedAmount
        );
    }

    // ============ Payer Actions ============

    /// @notice Request a refund. Only payer can call.
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount being requested for refund
    function requestRefund(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint120 amount)
        external
        operatorNotZero(paymentInfo)
        onlyPayer(paymentInfo)
    {
        if (amount == 0) revert ZeroRefundAmount();

        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);

        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[paymentInfoHash];
        if (existingRequest.paymentInfoHash != bytes32(0) && existingRequest.status != RequestStatus.Cancelled) {
            revert RequestAlreadyExists();
        }

        // Store paymentInfo by hash (idempotent -- same hash always maps to same data)
        if (paymentInfoStore[paymentInfoHash].operator == address(0)) {
            paymentInfoStore[paymentInfoHash] = paymentInfo;
        }

        // Create or update refund request
        refundRequests[paymentInfoHash] = RefundRequestData({
            paymentInfoHash: paymentInfoHash, amount: amount, approvedAmount: 0, status: RequestStatus.Pending
        });

        // Update indexing mappings (only add if not already indexed)
        _addPayerRequest(paymentInfo.payer, paymentInfoHash);
        _addReceiverRequest(paymentInfo.receiver, paymentInfoHash);
        _addOperatorRequest(paymentInfo.operator, paymentInfoHash);

        emit RefundRequested(paymentInfo, paymentInfo.payer, paymentInfo.receiver, amount);
    }

    /// @notice Cancel a pending refund request. Only payer can call.
    /// @param paymentInfo PaymentInfo struct
    function cancelRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        operatorNotZero(paymentInfo)
        onlyPayer(paymentInfo)
    {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);

        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        // Record cancel history before updating status
        uint256 index = cancelCount[paymentInfoHash];
        cancelledAmounts[paymentInfoHash][index] = request.amount;
        cancelCount[paymentInfoHash] = index + 1;

        request.status = RequestStatus.Cancelled;

        emit RefundRequestCancelled(paymentInfo, msg.sender);
    }

    // ============ Arbiter Actions ============

    /// @notice Deny a refund request. Only arbiter can call.
    ///         Arbiter reviewed evidence and rejects the refund claim.
    /// @param paymentInfo PaymentInfo struct
    function deny(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        operatorNotZero(paymentInfo)
        onlyArbiter
    {
        _setStatus(paymentInfo, RequestStatus.Denied);
    }

    /// @notice Refuse a refund request. Only arbiter can call.
    ///         Arbiter won't consider the request (spam, out of jurisdiction, invalid).
    /// @param paymentInfo PaymentInfo struct
    function refuse(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        operatorNotZero(paymentInfo)
        onlyArbiter
    {
        _setStatus(paymentInfo, RequestStatus.Refused);
    }

    // ============ Internal ============

    function _setStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, RequestStatus newStatus) internal {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);

        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        RequestStatus oldStatus = request.status;
        request.status = newStatus;

        emit RefundRequestStatusUpdated(paymentInfo, oldStatus, newStatus, msg.sender, 0);
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

    /// @notice Check if a caller is the arbiter.
    /// @param caller The address to check
    /// @return True if caller is the ARBITER
    function isArbiter(AuthCaptureEscrow.PaymentInfo calldata, address caller) external view returns (bool) {
        return caller == ARBITER;
    }

    function getRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (RefundRequestData memory)
    {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);
        RefundRequestData memory request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }

    function hasRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);
        return refundRequests[paymentInfoHash].paymentInfoHash != bytes32(0);
    }

    function getRefundRequestStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (RequestStatus)
    {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);
        return refundRequests[paymentInfoHash].status;
    }

    function getRefundRequestByKey(bytes32 paymentInfoHash) external view returns (RefundRequestData memory) {
        RefundRequestData memory request = refundRequests[paymentInfoHash];
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

    function getCancelCount(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);
        return cancelCount[paymentInfoHash];
    }

    function getCancelledAmount(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 cancelIndex)
        external
        view
        returns (uint120)
    {
        PaymentOperator op = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = op.ESCROW().getHash(paymentInfo);
        if (cancelIndex >= cancelCount[paymentInfoHash]) revert IndexOutOfBounds();
        return cancelledAmounts[paymentInfoHash][cancelIndex];
    }
}
