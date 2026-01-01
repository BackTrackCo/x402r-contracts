// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {CommercePaymentsOperator} from "../operator/CommercePaymentsOperator.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests for Base Commerce Payments authorizations
 * @dev Stores refund requests with authorizationId, ipfsLink, and status.
 *      Only the user who made the authorization can create a request.
 *      Pre-capture: merchant OR arbiter can approve
 *      Post-capture: merchant ONLY can approve
 */
contract RefundRequest {
    // Status enum: 0 = Pending, 1 = Approved, 2 = Denied
    enum RequestStatus {
        Pending,
        Approved,
        Denied
    }

    struct RefundRequestData {
        address payer;          // Payer who made the authorization
        bytes32 authorizationId; // Authorization ID from operator contract
        string ipfsLink;        // IPFS link to refund request details/evidence
        RequestStatus status;   // Current status of the request
    }

    // Reference to the operator contract
    CommercePaymentsOperator public immutable OPERATOR;

    // authorizationId → refund request
    mapping(bytes32 => RefundRequestData) private refundRequests;

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

    /// @notice Constructor
    /// @param _operator Address of the CommercePaymentsOperator contract
    constructor(address _operator) {
        require(_operator != address(0), "Zero operator");
        OPERATOR = CommercePaymentsOperator(_operator);
    }

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
        
        // Check if request already exists
        RefundRequestData storage existingRequest = refundRequests[authorizationId];
        require(existingRequest.payer == address(0), "Request already exists");
        
        // Create new refund request
        refundRequests[authorizationId] = RefundRequestData({
            payer: payer,
            authorizationId: authorizationId,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending
        });
        
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

    /// @notice Update the status of a refund request
    /// @param authorizationId The authorization ID
    /// @param newStatus The new status (Approved or Denied)
    /// @dev Pre-capture: merchant OR arbiter can approve
    ///      Post-capture: merchant ONLY can approve
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatus(
        bytes32 authorizationId,
        RequestStatus newStatus
    ) external {
        require(newStatus == RequestStatus.Approved || newStatus == RequestStatus.Denied, "Invalid status");
        
        RefundRequestData storage request = refundRequests[authorizationId];
        require(request.payer != address(0), "Request does not exist");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Get authorization data from operator contract
        CommercePaymentsOperator.AuthorizationData memory auth = OPERATOR.getAuthorization(authorizationId);
        address merchant = auth.merchant;
        address arbiter = auth.arbiter;
        require(merchant != address(0), "Invalid merchant");
        require(arbiter != address(0), "Invalid arbiter");
        
        // Check if authorization is captured
        bool isCaptured = auth.captured;
        
        // CRITICAL: Enforce approval rules based on capture status
        // Use operator contract's access control to verify caller
        if (isCaptured) {
            // Post-capture: merchant ONLY can approve
            require(OPERATOR.isMerchantRegistered(merchant), "Merchant not registered");
            require(msg.sender == merchant, "Post-capture refund requires merchant approval only");
        } else {
            // Pre-capture: merchant OR arbiter can approve
            require(OPERATOR.isMerchantRegistered(merchant), "Merchant not registered");
            require(
                msg.sender == merchant || msg.sender == arbiter,
                "Pre-capture refund requires arbiter or merchant approval"
            );
        }
        
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
    /// @return The status of the request (0 = Pending, 1 = Approved, 2 = Denied)
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
}

