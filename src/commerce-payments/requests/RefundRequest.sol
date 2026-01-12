// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.33 <0.9.0;

import {ArbiterationOperator} from "../operator/ArbiterationOperator.sol";
import {RefundRequestAccess} from "./RefundRequestAccess.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests for Base Commerce Payments authorizations
 * @dev Stores refund requests with authorizationId, ipfsLink, and status.
 *      Only the user who made the authorization can create a request.
 *      In escrow: merchant OR arbiter can approve
 *      Post escrow: merchant ONLY can approve
 */
contract RefundRequest is RefundRequestAccess {
    // Status enum: 0 = Pending, 1 = Approved, 2 = Denied, 3 = Cancelled
    enum RequestStatus {
        Pending,
        Approved,
        Denied,
        Cancelled
    }

    struct RefundRequestData {
        address payer;          // Payer who made the authorization
        bytes32 authorizationId; // Authorization ID from operator contract
        address merchantPayout; // Merchant payout address (stored directly)
        string ipfsLink;        // IPFS link to refund request details/evidence
        RequestStatus status;   // Current status of the request
        uint256 originalAmount; // Original authorization amount (stored when request is created)
    }

    // authorizationId → refund request
    mapping(bytes32 => RefundRequestData) private refundRequests;
    // payer → array of authorization IDs (for iteration)
    mapping(address => bytes32[]) private payerRefundRequests;
    // merchant → array of authorization IDs (for iteration)
    mapping(address => bytes32[]) private merchantRefundRequests;
    // arbiter → array of authorization IDs (for iteration)
    mapping(address => bytes32[]) private arbiterRefundRequests;

    // Events
    event RefundRequested(
        bytes32 indexed authorizationId,
        address indexed payer,
        string ipfsLink
    );
    
    event RefundRequestStatusUpdated(
        bytes32 indexed authorizationId,
        RequestStatus oldStatus,
        RequestStatus newStatus,
        address updatedBy
    );
    
    event RefundRequestCancelled(
        bytes32 indexed authorizationId,
        address indexed payer,
        address cancelledBy
    );

    /// @notice Constructor
    /// @param _operator Address of the ArbiterationOperator contract
    constructor(address _operator) RefundRequestAccess(_operator) {}

    /// @notice Request a refund for an authorization
    /// @param authorizationId The authorization ID to request refund for
    /// @param ipfsLink IPFS link to refund request details/evidence
    /// @dev Only the payer who made the authorization can request a refund
    ///      The authorization must exist in the operator contract
    function requestRefund(bytes32 authorizationId, string calldata ipfsLink) external {
        require(bytes(ipfsLink).length > 0, "Empty IPFS link");
        
        // Verify authorization exists in operator contract
        address payer = OPERATOR.getPayer(authorizationId);
        require(payer != address(0), "Authorization does not exist");
        require(msg.sender == payer, "Only payer can request refund");
        
        // Get authorization data to get merchant, arbiter, and amount
        ArbiterationOperator.AuthorizationData memory auth = OPERATOR.getAuthorization(authorizationId);
        address merchantPayout = auth.merchant;
        address arbiter = auth.arbiter;
        require(merchantPayout != address(0), "Invalid merchant payout");
        require(arbiter != address(0), "Invalid arbiter");
        
        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[authorizationId];
        if (existingRequest.payer != address(0)) {
            require(existingRequest.status == RequestStatus.Cancelled, "Request already exists");
            // If cancelled, we'll reuse the existing request slot and update it
        }
        
        // Create or update refund request with merchantPayout and original amount
        refundRequests[authorizationId] = RefundRequestData({
            payer: payer,
            authorizationId: authorizationId,
            merchantPayout: merchantPayout,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending,
            originalAmount: auth.amount // Store original authorization amount
        });
        
        // Update indexing arrays (only add if not already in arrays)
        // For cancelled requests, they were removed from arrays, so we need to add them back
        bytes32[] storage payerAuthIds = payerRefundRequests[payer];
        bool foundInPayerArray = false;
        for (uint256 i = 0; i < payerAuthIds.length; i++) {
            if (payerAuthIds[i] == authorizationId) {
                foundInPayerArray = true;
                break;
            }
        }
        if (!foundInPayerArray) {
            payerAuthIds.push(authorizationId);
        }
        
        bytes32[] storage merchantAuthIds = merchantRefundRequests[merchantPayout];
        bool foundInMerchantArray = false;
        for (uint256 i = 0; i < merchantAuthIds.length; i++) {
            if (merchantAuthIds[i] == authorizationId) {
                foundInMerchantArray = true;
                break;
            }
        }
        if (!foundInMerchantArray) {
            merchantAuthIds.push(authorizationId);
        }
        
        bytes32[] storage arbiterAuthIds = arbiterRefundRequests[arbiter];
        bool foundInArbiterArray = false;
        for (uint256 i = 0; i < arbiterAuthIds.length; i++) {
            if (arbiterAuthIds[i] == authorizationId) {
                foundInArbiterArray = true;
                break;
            }
        }
        if (!foundInArbiterArray) {
            arbiterAuthIds.push(authorizationId);
        }
        
        emit RefundRequested(authorizationId, payer, ipfsLink);
    }

    /// @notice Get a refund request
    /// @param authorizationId The authorization ID
    /// @return The refund request data
    function getRefundRequest(bytes32 authorizationId)
        external
        view
        returns (RefundRequestData memory)
    {
        RefundRequestData memory request = refundRequests[authorizationId];
        require(request.payer != address(0), "Request does not exist");
        return request;
    }

    /// @notice Update the status of a refund request (in escrow)
    /// @param authorizationId The authorization ID
    /// @param newStatus The new status (Approved or Denied)
    /// @dev Only merchant OR arbiter can approve in-escrow refunds
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatusInEscrow(
        bytes32 authorizationId,
        RequestStatus newStatus
    ) public onlyMerchantOrArbiterForAuthorization(authorizationId) onlyInEscrow(authorizationId) {
        require(newStatus == RequestStatus.Approved || newStatus == RequestStatus.Denied, "Invalid status");
        
        RefundRequestData storage request = refundRequests[authorizationId];
        require(request.payer != address(0), "Request does not exist");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Get authorization data for internal update
        ArbiterationOperator.AuthorizationData memory auth = OPERATOR.getAuthorization(authorizationId);
        _updateStatusInternal(authorizationId, newStatus, auth, false);
    }
    
    /// @notice Update the status of a refund request (post escrow)
    /// @param authorizationId The authorization ID
    /// @param newStatus The new status (Approved or Denied)
    /// @dev Only merchant can approve post-escrow refunds
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatusPostEscrow(
        bytes32 authorizationId,
        RequestStatus newStatus
    ) public onlyMerchantForAuthorization(authorizationId) onlyPostEscrow(authorizationId) {
        require(newStatus == RequestStatus.Approved || newStatus == RequestStatus.Denied, "Invalid status");
        
        RefundRequestData storage request = refundRequests[authorizationId];
        require(request.payer != address(0), "Request does not exist");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Get authorization data for internal update
        ArbiterationOperator.AuthorizationData memory auth = OPERATOR.getAuthorization(authorizationId);
        _updateStatusInternal(authorizationId, newStatus, auth, true);
    }
    
    /// @notice Internal function to update refund request status
    /// @param authorizationId The authorization ID
    /// @param newStatus The new status
    /// @param auth The authorization data
    /// @param isCaptured Whether the authorization is captured
    function _updateStatusInternal(
        bytes32 authorizationId,
        RequestStatus newStatus,
        ArbiterationOperator.AuthorizationData memory auth,
        bool isCaptured
    ) internal {
        // If denying, check authorization still exists (prevent denying after full refund)
        if (newStatus == RequestStatus.Denied) {
            // Verify authorization still exists and hasn't been fully refunded
            // For in escrow: check if refundedAmount >= amount
            // For post escrow: check if refundedAmount >= capturedAmount
            bool fullyRefunded = isCaptured 
                ? auth.refundedAmount >= auth.capturedAmount 
                : auth.refundedAmount >= auth.amount;
            require(!fullyRefunded, "Cannot deny: authorization already fully refunded");
        }
        
        RefundRequestData storage request = refundRequests[authorizationId];
        RequestStatus oldStatus = request.status;
        request.status = newStatus;
        
        emit RefundRequestStatusUpdated(authorizationId, oldStatus, newStatus, msg.sender);
    }

    /// @notice Check if a refund request exists
    /// @param authorizationId The authorization ID
    /// @return True if request exists, false otherwise
    function hasRefundRequest(bytes32 authorizationId) external view returns (bool) {
        return refundRequests[authorizationId].payer != address(0);
    }

    /// @notice Get the status of a refund request
    /// @param authorizationId The authorization ID
    /// @return The status of the request (0 = Pending, 1 = Approved, 2 = Denied, 3 = Cancelled)
    /// @dev Returns 0 if request doesn't exist (which also means Pending)
    function getRefundRequestStatus(bytes32 authorizationId)
        external
        view
        returns (uint8)
    {
        RefundRequestData memory request = refundRequests[authorizationId];
        if (request.payer == address(0)) {
            return uint8(RequestStatus.Pending);
        }
        return uint8(request.status);
    }

    /// @notice Get all refund requests for a payer
    /// @param payer The payer address
    /// @return Array of refund request data
    function getPayerRefundRequests(address payer) 
        external 
        view 
        returns (RefundRequestData[] memory) {
        bytes32[] memory authIds = payerRefundRequests[payer];
        RefundRequestData[] memory requests = new RefundRequestData[](authIds.length);
        for (uint256 i = 0; i < authIds.length; i++) {
            requests[i] = refundRequests[authIds[i]];
        }
        return requests;
    }

    /// @notice Get all refund requests for a merchant
    /// @param merchant The merchant payout address
    /// @return Array of refund request data
    function getMerchantRefundRequests(address merchant) 
        external 
        view 
        returns (RefundRequestData[] memory) {
        bytes32[] memory authIds = merchantRefundRequests[merchant];
        RefundRequestData[] memory requests = new RefundRequestData[](authIds.length);
        for (uint256 i = 0; i < authIds.length; i++) {
            requests[i] = refundRequests[authIds[i]];
        }
        return requests;
    }

    /// @notice Get all refund requests for an arbiter
    /// @param arbiter The arbiter address
    /// @return Array of refund request data
    function getArbiterRefundRequests(address arbiter) 
        external 
        view 
        returns (RefundRequestData[] memory) {
        bytes32[] memory authIds = arbiterRefundRequests[arbiter];
        RefundRequestData[] memory requests = new RefundRequestData[](authIds.length);
        for (uint256 i = 0; i < authIds.length; i++) {
            requests[i] = refundRequests[authIds[i]];
        }
        return requests;
    }

    /// @notice Cancel a refund request
    /// @param authorizationId The authorization ID of the refund request to cancel
    /// @dev Only the payer who created the request can cancel it
    ///      Request must be in Pending status
    function cancelRefundRequest(bytes32 authorizationId) external {
        address payer = msg.sender;
        
        RefundRequestData storage request = refundRequests[authorizationId];
        require(request.payer != address(0), "Request does not exist");
        require(request.payer == payer, "Not request owner");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Update status to Cancelled
        request.status = RequestStatus.Cancelled;
        
        // Don't remove from indexing arrays so cancelled requests appear in archived section
        // This allows users to see their cancellation history
        // Note: If a new request is made for the same authorizationId, it will overwrite this cancelled request
        
        emit RefundRequestCancelled(authorizationId, payer, msg.sender);
    }
}

