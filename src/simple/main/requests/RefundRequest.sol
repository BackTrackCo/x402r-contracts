// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {EscrowAccess} from "../escrow/EscrowAccess.sol";
import {Escrow} from "../escrow/Escrow.sol";

/**
 * @title RefundRequest
 * @notice Contract for managing refund requests for escrow deposits
 * @dev Stores refund requests with user, depositNonce, ipfsLink, and status.
 *      Only the user who made the deposit can create a request.
 *      Only the merchant or arbiter can update the status.
 */
contract RefundRequest {
    // Status enum: 0 = Pending, 1 = Approved, 2 = Denied
    enum RequestStatus {
        Pending,
        Approved,
        Denied
    }

    struct RefundRequestData {
        address user;           // User who made the deposit
        uint256 depositNonce;   // Deposit nonce from Escrow
        string ipfsLink;        // IPFS link to refund request details/evidence
        RequestStatus status;   // Current status of the request
    }

    // Reference to the Escrow contract
    Escrow public immutable ESCROW;

    // user → depositNonce → refund request
    mapping(address => mapping(uint256 => RefundRequestData)) private refundRequests;

    // Events
    event RefundRequested(
        address indexed user,
        uint256 indexed depositNonce,
        string ipfsLink
    );
    
    event RefundRequestStatusUpdated(
        address indexed user,
        uint256 indexed depositNonce,
        RequestStatus oldStatus,
        RequestStatus newStatus,
        address updatedBy
    );

    /// @notice Constructor
    /// @param _escrow Address of the Escrow contract
    constructor(address _escrow) {
        require(_escrow != address(0), "Zero escrow");
        ESCROW = Escrow(_escrow);
    }

    /// @notice Request a refund for a deposit
    /// @param depositNonce The nonce of the deposit to request refund for
    /// @param ipfsLink IPFS link to refund request details/evidence
    /// @dev Only the user who made the deposit can request a refund
    ///      The deposit must exist in the Escrow contract
    function requestRefund(uint256 depositNonce, string calldata ipfsLink) external {
        address user = msg.sender;
        
        require(bytes(ipfsLink).length > 0, "Empty IPFS link");
        
        // Verify deposit exists in Escrow
        (uint256 principal, , , address merchantPayout) = ESCROW.getDeposit(user, depositNonce);
        require(principal > 0, "Deposit does not exist");
        require(merchantPayout != address(0), "Invalid merchant payout");
        
        // Check if request already exists
        RefundRequestData storage existingRequest = refundRequests[user][depositNonce];
        require(existingRequest.user == address(0), "Request already exists");
        
        // Create new refund request
        refundRequests[user][depositNonce] = RefundRequestData({
            user: user,
            depositNonce: depositNonce,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending
        });
        
        emit RefundRequested(user, depositNonce, ipfsLink);
    }

    /// @notice Get a refund request
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    /// @return The refund request data
    function getRefundRequest(address user, uint256 depositNonce)
        external
        view
        returns (RefundRequestData memory)
    {
        RefundRequestData memory request = refundRequests[user][depositNonce];
        require(request.user != address(0), "Request does not exist");
        return request;
    }

    /// @notice Update the status of a refund request
    /// @param user The user address who made the deposit
    /// @param depositNonce The deposit nonce
    /// @param newStatus The new status (Approved or Denied)
    /// @dev Only the merchant or arbiter for the deposit's merchant can update status
    ///      Status can only be changed from Pending to Approved or Denied
    function updateStatus(
        address user,
        uint256 depositNonce,
        RequestStatus newStatus
    ) external {
        require(newStatus == RequestStatus.Approved || newStatus == RequestStatus.Denied, "Invalid status");
        
        RefundRequestData storage request = refundRequests[user][depositNonce];
        require(request.user != address(0), "Request does not exist");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Verify the caller is merchant or arbiter for this deposit
        (, , , address merchantPayout) = ESCROW.getDeposit(user, depositNonce);
        require(merchantPayout != address(0), "Invalid merchant payout");
        
        address arbiter = ESCROW.getArbiter(merchantPayout);
        require(
            msg.sender == merchantPayout || msg.sender == arbiter,
            "Not merchant or arbiter"
        );
        
        RequestStatus oldStatus = request.status;
        request.status = newStatus;
        
        emit RefundRequestStatusUpdated(user, depositNonce, oldStatus, newStatus, msg.sender);
    }

    /// @notice Check if a refund request exists
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    /// @return True if request exists, false otherwise
    function hasRefundRequest(address user, uint256 depositNonce) external view returns (bool) {
        return refundRequests[user][depositNonce].user != address(0);
    }

    /// @notice Get the status of a refund request
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    /// @return The status of the request (0 = Pending, 1 = Approved, 2 = Denied)
    /// @dev Returns 0 if request doesn't exist (which also means Pending)
    function getRefundRequestStatus(address user, uint256 depositNonce)
        external
        view
        returns (uint8)
    {
        RefundRequestData memory request = refundRequests[user][depositNonce];
        if (request.user == address(0)) {
            return uint8(RequestStatus.Pending);
        }
        return uint8(request.status);
    }
}

