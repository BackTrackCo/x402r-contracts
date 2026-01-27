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
 */
contract RefundRequest is RefundRequestAccess {
    struct RefundRequestData {
        bytes32 paymentInfoHash; // Hash of PaymentInfo
        uint256 nonce; // Record index this refund is for
        uint120 amount; // Amount being requested for refund
        RequestStatus status; // Current status of the request
    }

    // compositeKey => refund request
    // compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce))
    mapping(bytes32 => RefundRequestData) private refundRequests;
    // payer => array of composite keys (for iteration)
    mapping(address => bytes32[]) private payerRefundRequests;
    // receiver => array of composite keys (for iteration)
    mapping(address => bytes32[]) private receiverRefundRequests;
    // O(1) existence checks for array deduplication
    mapping(address => mapping(bytes32 => bool)) private payerRefundRequestExists;
    mapping(address => mapping(bytes32 => bool)) private receiverRefundRequestExists;

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

        // Update indexing arrays (only add if not already in arrays)
        _addPayerRequest(paymentInfo.payer, compositeKey);
        _addReceiverRequest(paymentInfo.receiver, compositeKey);

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

    /// @notice Add key to payer's request array if not already present (O(1) check)
    function _addPayerRequest(address payer, bytes32 key) internal {
        if (payerRefundRequestExists[payer][key]) return;
        payerRefundRequestExists[payer][key] = true;
        payerRefundRequests[payer].push(key);
    }

    /// @notice Add key to receiver's request array if not already present (O(1) check)
    function _addReceiverRequest(address receiver, bytes32 key) internal {
        if (receiverRefundRequestExists[receiver][key]) return;
        receiverRefundRequestExists[receiver][key] = true;
        receiverRefundRequests[receiver].push(key);
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

    /// @notice Get all refund request keys for a payer
    /// @param payer The payer address
    /// @return Array of composite keys
    function getPayerRefundRequestKeys(address payer) external view returns (bytes32[] memory) {
        return payerRefundRequests[payer];
    }

    /// @notice Get all refund request keys for a receiver (merchant)
    /// @param receiver The receiver address
    /// @return Array of composite keys
    function getReceiverRefundRequestKeys(address receiver) external view returns (bytes32[] memory) {
        return receiverRefundRequests[receiver];
    }

    /// @notice Get refund request data by composite key
    /// @param compositeKey The keccak256(paymentInfoHash, nonce) key
    /// @return The refund request data
    function getRefundRequestByKey(bytes32 compositeKey) external view returns (RefundRequestData memory) {
        RefundRequestData memory request = refundRequests[compositeKey];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }
}
