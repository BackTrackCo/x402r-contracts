// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorAccess} from "../../operator/arbitration/ArbitrationOperatorAccess.sol";
import {RefundRequestAccess} from "./RefundRequestAccess.sol";
import {RequestStatus} from "../types/Types.sol";
import {
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending,
    InvalidStatus,
    FullyRefunded
} from "../types/Errors.sol";
import {
    RefundRequested,
    RefundRequestStatusUpdated,
    RefundRequestCancelled
} from "../types/Events.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests - operator-agnostic, takes PaymentInfo directly
 * @dev Works with any ArbitrationOperator. Escrow is source of truth.
 *      Only the payer who made the authorization can create a request.
 *      In escrow: receiver (merchant) OR arbiter can approve
 *      Post escrow: receiver (merchant) ONLY can approve
 */
contract RefundRequest is ArbitrationOperatorAccess, RefundRequestAccess {
    struct RefundRequestData {
        bytes32 paymentInfoHash;    // Hash of PaymentInfo
        RequestStatus status;       // Current status of the request
    }

    // paymentInfoHash => refund request
    mapping(bytes32 => RefundRequestData) private refundRequests;
    // payer => array of paymentInfoHashes (for iteration)
    mapping(address => bytes32[]) private payerRefundRequests;
    // receiver => array of paymentInfoHashes (for iteration)
    mapping(address => bytes32[]) private receiverRefundRequests;
    // O(1) existence checks for array deduplication
    mapping(address => mapping(bytes32 => bool)) private payerRefundRequestExists;
    mapping(address => mapping(bytes32 => bool)) private receiverRefundRequestExists;

    /// @notice Request a refund for an authorization
    /// @param paymentInfo PaymentInfo struct
    /// @dev Only the payer can request a refund
    function requestRefund(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo
    ) external operatorNotZero(paymentInfo) onlyPayer(paymentInfo) {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[paymentInfoHash];
        if (existingRequest.paymentInfoHash != bytes32(0) && existingRequest.status != RequestStatus.Cancelled) {
            revert RequestAlreadyExists();
        }

        // Create or update refund request
        refundRequests[paymentInfoHash] = RefundRequestData({
            paymentInfoHash: paymentInfoHash,
            status: RequestStatus.Pending
        });

        // Update indexing arrays (only add if not already in arrays)
        _addPayerRequest(paymentInfo.payer, paymentInfoHash);
        _addReceiverRequest(paymentInfo.receiver, paymentInfoHash);

        emit RefundRequested(paymentInfo, paymentInfo.payer, paymentInfo.receiver);
    }

    /// @notice Update the status of a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @param newStatus The new status (Approved or Denied)
    /// @dev In escrow: receiver OR arbiter can approve/deny
    ///      Post escrow: only receiver can approve/deny
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatus(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        RequestStatus newStatus
    ) external operatorNotZero(paymentInfo) onlyAuthorizedForRefundStatus(paymentInfo) {
        _updateStatus(paymentInfo, newStatus);
    }

    /// @notice Cancel a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @dev Only the payer who created the request can cancel it
    ///      Request must be in Pending status
    function cancelRefundRequest(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo
    ) external operatorNotZero(paymentInfo) onlyPayer(paymentInfo) {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        request.status = RequestStatus.Cancelled;

        emit RefundRequestCancelled(paymentInfo, msg.sender);
    }

    // ============ Internal Functions ============

    /// @notice Internal function to update refund request status
    function _updateStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, RequestStatus newStatus) internal {
        if (newStatus != RequestStatus.Approved && newStatus != RequestStatus.Denied) {
            revert InvalidStatus();
        }

        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        // If denying, verify not already fully refunded/voided
        if (newStatus == RequestStatus.Denied) {
            (, uint120 capturableAmount, uint120 refundableAmount) = operator.ESCROW().paymentState(paymentInfoHash);
            if (capturableAmount == 0 && refundableAmount == 0) revert FullyRefunded();
        }

        RequestStatus oldStatus = request.status;
        request.status = newStatus;

        emit RefundRequestStatusUpdated(paymentInfo, oldStatus, newStatus, msg.sender);
    }

    /// @notice Add hash to payer's request array if not already present (O(1) check)
    function _addPayerRequest(address payer, bytes32 hash) internal {
        if (payerRefundRequestExists[payer][hash]) return;
        payerRefundRequestExists[payer][hash] = true;
        payerRefundRequests[payer].push(hash);
    }

    /// @notice Add hash to receiver's request array if not already present (O(1) check)
    function _addReceiverRequest(address receiver, bytes32 hash) internal {
        if (receiverRefundRequestExists[receiver][hash]) return;
        receiverRefundRequestExists[receiver][hash] = true;
        receiverRefundRequests[receiver].push(hash);
    }

    // ============ View Functions ============

    /// @notice Get a refund request by PaymentInfo
    /// @param paymentInfo PaymentInfo struct
    /// @return The refund request data
    function getRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (RefundRequestData memory)
    {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        RefundRequestData memory request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }

    /// @notice Check if a refund request exists
    /// @param paymentInfo PaymentInfo struct
    /// @return True if request exists, false otherwise
    function hasRefundRequest(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        return refundRequests[paymentInfoHash].paymentInfoHash != bytes32(0);
    }

    /// @notice Get the status of a refund request
    /// @param paymentInfo PaymentInfo struct
    /// @return The status of the request
    function getRefundRequestStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (RequestStatus)
    {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        return refundRequests[paymentInfoHash].status;
    }

    /// @notice Get all refund request hashes for a payer
    /// @param payer The payer address
    /// @return Array of payment info hashes
    function getPayerRefundRequestHashes(address payer)
        external
        view
        returns (bytes32[] memory)
    {
        return payerRefundRequests[payer];
    }

    /// @notice Get all refund request hashes for a receiver (merchant)
    /// @param receiver The receiver address
    /// @return Array of payment info hashes
    function getReceiverRefundRequestHashes(address receiver)
        external
        view
        returns (bytes32[] memory)
    {
        return receiverRefundRequests[receiver];
    }

    /// @notice Get refund request data by hash
    /// @param paymentInfoHash The payment info hash
    /// @return The refund request data
    function getRefundRequestByHash(bytes32 paymentInfoHash)
        external
        view
        returns (RefundRequestData memory)
    {
        RefundRequestData memory request = refundRequests[paymentInfoHash];
        if (request.paymentInfoHash == bytes32(0)) revert RequestDoesNotExist();
        return request;
    }
}
