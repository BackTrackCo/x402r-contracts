// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {RefundRequestAccess} from "./RefundRequestAccess.sol";
import {RequestStatus} from "./Types.sol";
import {
    EmptyIpfsLink,
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending,
    InvalidStatus,
    FullyRefunded
} from "./Errors.sol";
import {
    RefundRequested,
    RefundRequestStatusUpdated,
    RefundRequestCancelled
} from "./Events.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests for Base Commerce Payments authorizations
 * @dev Stores refund requests with paymentInfoHash, ipfsLink, and status.
 *      Only the payer who made the authorization can create a request.
 *      In escrow: receiver (merchant) OR arbiter can approve
 *      Post escrow: receiver (merchant) ONLY can approve
 */
contract RefundRequest is RefundRequestAccess {
    struct RefundRequestData {
        bytes32 paymentInfoHash;    // Hash of PaymentInfo from operator contract
        string ipfsLink;            // IPFS link to refund request details/evidence
        RequestStatus status;       // Current status of the request
    }

    // paymentInfoHash => refund request
    mapping(bytes32 => RefundRequestData) private refundRequests;
    // payer => array of paymentInfoHashes (for iteration)
    mapping(address => bytes32[]) private payerRefundRequests;
    // receiver => array of paymentInfoHashes (for iteration)
    mapping(address => bytes32[]) private receiverRefundRequests;

    /// @notice Constructor
    /// @param _operator Address of the ArbitrationOperator contract
    constructor(address _operator) RefundRequestAccess(_operator) {}

    /// @notice Request a refund for an authorization
    /// @param paymentInfoHash The hash of the PaymentInfo struct
    /// @param ipfsLink IPFS link to refund request details/evidence
    /// @dev Only the payer can request a refund
    ///      The authorization must exist in the operator contract
    function requestRefund(
        bytes32 paymentInfoHash,
        string calldata ipfsLink
    ) external paymentMustExist(paymentInfoHash) validOperatorByHash(paymentInfoHash) onlyPayerByHash(paymentInfoHash) {
        if (bytes(ipfsLink).length == 0) revert EmptyIpfsLink();

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = OPERATOR.getPaymentInfo(paymentInfoHash);

        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[paymentInfoHash];
        if (bytes(existingRequest.ipfsLink).length != 0 && existingRequest.status != RequestStatus.Cancelled) {
            revert RequestAlreadyExists();
        }

        // Create or update refund request
        refundRequests[paymentInfoHash] = RefundRequestData({
            paymentInfoHash: paymentInfoHash,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending
        });

        // Update indexing arrays (only add if not already in arrays)
        _addToArrayIfNotExists(payerRefundRequests[paymentInfo.payer], paymentInfoHash);
        _addToArrayIfNotExists(receiverRefundRequests[paymentInfo.receiver], paymentInfoHash);

        emit RefundRequested(paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, ipfsLink);
    }

    /// @notice Update the status of a refund request
    /// @param paymentInfoHash The hash of the PaymentInfo struct
    /// @param newStatus The new status (Approved or Denied)
    /// @dev In escrow: receiver OR arbiter can approve/deny
    ///      Post escrow: only receiver can approve/deny
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatus(
        bytes32 paymentInfoHash,
        RequestStatus newStatus
    ) external paymentMustExist(paymentInfoHash) validOperatorByHash(paymentInfoHash) onlyAuthorizedForRefundStatus(paymentInfoHash) {
        _updateStatus(paymentInfoHash, newStatus);
    }

    /// @notice Cancel a refund request
    /// @param paymentInfoHash The hash of the PaymentInfo struct
    /// @dev Only the payer who created the request can cancel it
    ///      Request must be in Pending status
    function cancelRefundRequest(
        bytes32 paymentInfoHash
    ) external paymentMustExist(paymentInfoHash) validOperatorByHash(paymentInfoHash) onlyPayerByHash(paymentInfoHash) {
        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (bytes(request.ipfsLink).length == 0) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        request.status = RequestStatus.Cancelled;

        emit RefundRequestCancelled(paymentInfoHash, msg.sender);
    }

    // ============ Internal Functions ============

    /// @notice Internal function to update refund request status
    function _updateStatus(bytes32 paymentInfoHash, RequestStatus newStatus) internal {
        if (newStatus != RequestStatus.Approved && newStatus != RequestStatus.Denied) {
            revert InvalidStatus();
        }

        RefundRequestData storage request = refundRequests[paymentInfoHash];
        if (bytes(request.ipfsLink).length == 0) revert RequestDoesNotExist();
        if (request.status != RequestStatus.Pending) revert RequestNotPending();

        // If denying, verify not already fully refunded/voided
        if (newStatus == RequestStatus.Denied) {
            (, uint120 capturableAmount, uint120 refundableAmount) = OPERATOR.ESCROW().paymentState(paymentInfoHash);
            if (capturableAmount == 0 && refundableAmount == 0) revert FullyRefunded();
        }

        RequestStatus oldStatus = request.status;
        request.status = newStatus;

        emit RefundRequestStatusUpdated(paymentInfoHash, oldStatus, newStatus, msg.sender);
    }

    /// @notice Add hash to array if not already present
    function _addToArrayIfNotExists(bytes32[] storage arr, bytes32 hash) internal {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == hash) return;
        }
        arr.push(hash);
    }

    // ============ View Functions ============

    /// @notice Get a refund request
    /// @param paymentInfoHash The payment info hash
    /// @return The refund request data
    function getRefundRequest(bytes32 paymentInfoHash)
        external
        view
        returns (RefundRequestData memory)
    {
        RefundRequestData memory request = refundRequests[paymentInfoHash];
        if (bytes(request.ipfsLink).length == 0) revert RequestDoesNotExist();
        return request;
    }

    /// @notice Check if a refund request exists
    /// @param paymentInfoHash The payment info hash
    /// @return True if request exists, false otherwise
    function hasRefundRequest(bytes32 paymentInfoHash) external view returns (bool) {
        return bytes(refundRequests[paymentInfoHash].ipfsLink).length != 0;
    }

    /// @notice Get the status of a refund request
    /// @param paymentInfoHash The payment info hash
    /// @return The status of the request
    function getRefundRequestStatus(bytes32 paymentInfoHash)
        external
        view
        returns (RequestStatus)
    {
        return refundRequests[paymentInfoHash].status;
    }

    /// @notice Get all refund requests for a payer
    /// @param payer The payer address
    /// @return Array of refund request data
    function getPayerRefundRequests(address payer)
        external
        view
        returns (RefundRequestData[] memory)
    {
        bytes32[] memory hashes = payerRefundRequests[payer];
        RefundRequestData[] memory requests = new RefundRequestData[](hashes.length);
        for (uint256 i = 0; i < hashes.length; i++) {
            requests[i] = refundRequests[hashes[i]];
        }
        return requests;
    }

    /// @notice Get all refund requests for a receiver (merchant)
    /// @param receiver The receiver address
    /// @return Array of refund request data
    function getReceiverRefundRequests(address receiver)
        external
        view
        returns (RefundRequestData[] memory)
    {
        bytes32[] memory hashes = receiverRefundRequests[receiver];
        RefundRequestData[] memory requests = new RefundRequestData[](hashes.length);
        for (uint256 i = 0; i < hashes.length; i++) {
            requests[i] = refundRequests[hashes[i]];
        }
        return requests;
    }

    /// @notice Get all refund requests for the arbiter
    /// @dev Returns all requests where the arbiter can take action (in escrow only)
    /// @param receiver The receiver to filter by (arbiter sees receiver's requests)
    /// @return Array of refund request data that are in escrow
    function getArbiterRefundRequests(address receiver)
        external
        view
        returns (RefundRequestData[] memory)
    {
        bytes32[] memory hashes = receiverRefundRequests[receiver];

        // First pass: count in-escrow requests
        uint256 count = 0;
        for (uint256 i = 0; i < hashes.length; i++) {
            if (isInEscrow(hashes[i]) && refundRequests[hashes[i]].status == RequestStatus.Pending) {
                count++;
            }
        }

        // Second pass: build result array
        RefundRequestData[] memory requests = new RefundRequestData[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < hashes.length; i++) {
            if (isInEscrow(hashes[i]) && refundRequests[hashes[i]].status == RequestStatus.Pending) {
                requests[index] = refundRequests[hashes[i]];
                index++;
            }
        }
        return requests;
    }
}
