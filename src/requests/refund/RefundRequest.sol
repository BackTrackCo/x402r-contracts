// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {RefundRequestAccess} from "./RefundRequestAccess.sol";
import {RequestStatus} from "../types/Types.sol";
import {
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending,
    InvalidStatus,
    FullyRefunded,
    ZeroRefundAmount
} from "../types/Errors.sol";
import {RefundRequested, RefundRequestStatusUpdated, RefundRequestCancelled} from "../types/Events.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests with condition-based authorization.
 * @dev Works with any PaymentOperator. Escrow is source of truth.
 *      Only the payer who made the authorization can create a request.
 *      Receiver can always approve/deny requests.
 *      While in escrow, anyone passing the operator's REFUND_IN_ESCROW_CONDITION can also
 *      approve/deny (address(0) condition = anyone allowed).
 *      Post escrow: only receiver can approve/deny.
 *      Actual refund execution is separate — gated by the operator's conditions.
 *
 *      Each refund request is keyed by (paymentInfoHash, nonce) where nonce is the
 *      record index from PaymentIndexRecorder. This allows multiple refund requests
 *      per payment (one per charge/action).
 *
 *      Storage uses mapping+counter pattern (matching PaymentIndexRecorder) for
 *      gas-efficient writes and paginated reads without unbounded arrays.
 */
contract RefundRequest is RefundRequestAccess {
    struct RefundRequestData {
        bytes32 paymentInfoHash; // Hash of PaymentInfo
        uint256 nonce; // Record index this refund is for
        uint120 amount; // Amount being requested for refund
        RequestStatus status; // Current status of the request
    }

    // ============ Errors ============

    error IndexOutOfBounds();

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

    // Cancel history: compositeKey => count of cancellations
    mapping(bytes32 => uint256) public cancelCount;
    // Cancel history: compositeKey => cancelIndex => cancelled amount
    mapping(bytes32 => mapping(uint256 => uint120)) private cancelledAmounts;

    /// @notice Request a refund for a specific record of a payment
    /// @param paymentInfo PaymentInfo struct
    /// @param amount Amount being requested for refund
    /// @param nonce Record index (from PaymentIndexRecorder) identifying which charge
    /// @dev Only the payer can request a refund
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

        // Create or update refund request
        refundRequests[compositeKey] = RefundRequestData({
            paymentInfoHash: paymentInfoHash, nonce: nonce, amount: amount, status: RequestStatus.Pending
        });

        // Update indexing mappings (only add if not already indexed)
        _addPayerRequest(paymentInfo.payer, compositeKey);
        _addReceiverRequest(paymentInfo.receiver, compositeKey);
        _addOperatorRequest(paymentInfo.operator, compositeKey);

        emit RefundRequested(paymentInfo, paymentInfo.payer, paymentInfo.receiver, amount, nonce);
    }

    /// @notice Update the status of a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    /// @param newStatus The new status (Approved or Denied)
    /// @dev Receiver can always approve/deny. While in escrow, anyone passing the
    ///      operator's REFUND_IN_ESCROW_CONDITION can also approve/deny.
    ///      Status can only be changed from Pending to Approved or Denied.
    function updateStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, RequestStatus newStatus)
        external
        operatorNotZero(paymentInfo)
        onlyAuthorizedForRefundStatus(paymentInfo)
    {
        _updateStatus(paymentInfo, nonce, newStatus);
    }

    /// @notice Cancel a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index identifying which refund request
    /// @dev Only the payer who created the request can cancel it
    ///      Request must be in Pending status
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

    // ============ Internal Functions ============

    /// @notice Internal function to update refund request status
    function _updateStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, RequestStatus newStatus)
        internal
    {
        if (newStatus != RequestStatus.Approved && newStatus != RequestStatus.Denied) {
            revert InvalidStatus();
        }

        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        RefundRequestData storage request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        // If denying, verify not already fully refunded/voided
        if (newStatus == RequestStatus.Denied) {
            (, uint120 capturableAmount, uint120 refundableAmount) = operator.ESCROW().paymentState(paymentInfoHash);
            if (capturableAmount == 0 && refundableAmount == 0) revert FullyRefunded();
        }

        RequestStatus oldStatus = request.status;
        request.status = newStatus;

        emit RefundRequestStatusUpdated(paymentInfo, oldStatus, newStatus, msg.sender, nonce);
    }

    /// @notice Add key to payer's index if not already present (O(1) check)
    function _addPayerRequest(address payer, bytes32 key) internal {
        if (payerRefundRequestExists[payer][key]) return;
        payerRefundRequestExists[payer][key] = true;
        payerRefundRequests[payer][payerRefundRequestCount[payer]] = key;
        payerRefundRequestCount[payer]++;
    }

    /// @notice Add key to receiver's index if not already present (O(1) check)
    function _addReceiverRequest(address receiver, bytes32 key) internal {
        if (receiverRefundRequestExists[receiver][key]) return;
        receiverRefundRequestExists[receiver][key] = true;
        receiverRefundRequests[receiver][receiverRefundRequestCount[receiver]] = key;
        receiverRefundRequestCount[receiver]++;
    }

    /// @notice Add key to operator's index if not already present (O(1) check)
    function _addOperatorRequest(address operator, bytes32 key) internal {
        if (operatorRefundRequestExists[operator][key]) return;
        operatorRefundRequestExists[operator][key] = true;
        operatorRefundRequests[operator][operatorRefundRequestCount[operator]] = key;
        operatorRefundRequestCount[operator]++;
    }

    // ============ View Functions ============

    /// @notice Get a refund request by PaymentInfo and nonce
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @return The refund request data
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

    /// @notice Check if a refund request exists
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @return True if request exists, false otherwise
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

    /// @notice Get the status of a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @return The status of the request
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

    /// @notice Get refund request data by composite key
    /// @param compositeKey The keccak256(paymentInfoHash, nonce) key
    /// @return The refund request data
    function getRefundRequestByKey(bytes32 compositeKey) external view returns (RefundRequestData memory) {
        RefundRequestData memory request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }

    // ============ Paginated View Functions ============

    /// @notice Get paginated refund request keys for a payer
    /// @param payer The payer address
    /// @param offset Starting index (0-based)
    /// @param count Number of keys to return
    /// @return keys Array of composite keys
    /// @return total Total number of refund requests for this payer
    function getPayerRefundRequests(address payer, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = payerRefundRequestCount[payer];

        if (offset >= total || count == 0) {
            return (new bytes32[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = payerRefundRequests[payer][offset + i];
        }

        return (keys, total);
    }

    /// @notice Get paginated refund request keys for a receiver
    /// @param receiver The receiver address
    /// @param offset Starting index (0-based)
    /// @param count Number of keys to return
    /// @return keys Array of composite keys
    /// @return total Total number of refund requests for this receiver
    function getReceiverRefundRequests(address receiver, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = receiverRefundRequestCount[receiver];

        if (offset >= total || count == 0) {
            return (new bytes32[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = receiverRefundRequests[receiver][offset + i];
        }

        return (keys, total);
    }

    /// @notice Get a single refund request key by index for a payer
    /// @param payer The payer address
    /// @param index Index of the request (0-based)
    /// @return The composite key at the specified index
    function getPayerRefundRequest(address payer, uint256 index) external view returns (bytes32) {
        if (index >= payerRefundRequestCount[payer]) revert IndexOutOfBounds();
        return payerRefundRequests[payer][index];
    }

    /// @notice Get a single refund request key by index for a receiver
    /// @param receiver The receiver address
    /// @param index Index of the request (0-based)
    /// @return The composite key at the specified index
    function getReceiverRefundRequest(address receiver, uint256 index) external view returns (bytes32) {
        if (index >= receiverRefundRequestCount[receiver]) revert IndexOutOfBounds();
        return receiverRefundRequests[receiver][index];
    }

    /// @notice Get paginated refund request keys for an operator
    /// @param operator The operator address
    /// @param offset Starting index (0-based)
    /// @param count Number of keys to return
    /// @return keys Array of composite keys
    /// @return total Total number of refund requests for this operator
    /// @dev Useful for arbiters who need to query requests by operators they have arbiter rights on
    function getOperatorRefundRequests(address operator, uint256 offset, uint256 count)
        external
        view
        returns (bytes32[] memory keys, uint256 total)
    {
        total = operatorRefundRequestCount[operator];

        if (offset >= total || count == 0) {
            return (new bytes32[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        keys = new bytes32[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            keys[i] = operatorRefundRequests[operator][offset + i];
        }

        return (keys, total);
    }

    /// @notice Get a single refund request key by index for an operator
    /// @param operator The operator address
    /// @param index Index of the request (0-based)
    /// @return The composite key at the specified index
    function getOperatorRefundRequest(address operator, uint256 index) external view returns (bytes32) {
        if (index >= operatorRefundRequestCount[operator]) revert IndexOutOfBounds();
        return operatorRefundRequests[operator][index];
    }

    // ============ Cancel History View Functions ============

    /// @notice Get the number of times a refund request has been cancelled
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @return The number of cancellations
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

    /// @notice Get the cancelled amount at a specific cancel index
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @param cancelIndex The cancel index (0-based, must be < getCancelCount)
    /// @return The amount that was requested when cancelled
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
