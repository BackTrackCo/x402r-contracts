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
    // Status enum: 0 = Pending, 1 = Approved, 2 = Denied, 3 = Cancelled
    enum RequestStatus {
        Pending,
        Approved,
        Denied,
        Cancelled
    }

    struct RefundRequestKey {
        address user;
        uint256 depositNonce;
    }

    struct RefundRequestData {
        address user;           // User who made the deposit
        uint256 depositNonce;   // Deposit nonce from Escrow
        address merchantPayout; // Merchant payout address (stored directly)
        string ipfsLink;        // IPFS link to refund request details/evidence
        RequestStatus status;   // Current status of the request
    }

    // Reference to the Escrow contract
    Escrow public immutable ESCROW;

    // user → depositNonce → refund request
    mapping(address => mapping(uint256 => RefundRequestData)) private refundRequests;
    // user → array of deposit nonces (for iteration)
    mapping(address => uint256[]) private userRefundRequestNonces;
    // merchant → array of refund request keys (for iteration)
    mapping(address => RefundRequestKey[]) private merchantRefundRequests;

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
    
    event RefundRequestCancelled(
        address indexed user,
        uint256 indexed depositNonce,
        address cancelledBy
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
        
        // Check if request already exists (allow re-requesting if cancelled)
        RefundRequestData storage existingRequest = refundRequests[user][depositNonce];
        if (existingRequest.user != address(0)) {
            require(existingRequest.status == RequestStatus.Cancelled, "Request already exists");
            // If cancelled, we'll reuse the existing request slot and update it
        }
        
        // Create or update refund request with merchantPayout
        refundRequests[user][depositNonce] = RefundRequestData({
            user: user,
            depositNonce: depositNonce,
            merchantPayout: merchantPayout,
            ipfsLink: ipfsLink,
            status: RequestStatus.Pending
        });
        
        // Update indexing arrays (only add if not already in arrays)
        // For cancelled requests, they were removed from arrays, so we need to add them back
        uint256[] storage userNonces = userRefundRequestNonces[user];
        bool foundInUserArray = false;
        for (uint256 i = 0; i < userNonces.length; i++) {
            if (userNonces[i] == depositNonce) {
                foundInUserArray = true;
                break;
            }
        }
        if (!foundInUserArray) {
            userNonces.push(depositNonce);
        }
        
        RefundRequestKey[] storage merchantKeys = merchantRefundRequests[merchantPayout];
        bool foundInMerchantArray = false;
        for (uint256 i = 0; i < merchantKeys.length; i++) {
            if (merchantKeys[i].user == user && merchantKeys[i].depositNonce == depositNonce) {
                foundInMerchantArray = true;
                break;
            }
        }
        if (!foundInMerchantArray) {
            merchantKeys.push(RefundRequestKey({
                user: user,
                depositNonce: depositNonce
            }));
        }
        
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
        // Use merchantPayout from struct instead of querying Escrow
        address merchantPayout = request.merchantPayout;
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
    /// @return The status of the request (0 = Pending, 1 = Approved, 2 = Denied, 3 = Cancelled)
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

    /// @notice Get all refund requests for a user
    /// @param user The user address
    /// @return Array of refund request data
    function getUserRefundRequests(address user) 
        external 
        view 
        returns (RefundRequestData[] memory) {
        uint256[] memory nonces = userRefundRequestNonces[user];
        RefundRequestData[] memory requests = new RefundRequestData[](nonces.length);
        for (uint256 i = 0; i < nonces.length; i++) {
            requests[i] = refundRequests[user][nonces[i]];
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
        RefundRequestKey[] memory keys = merchantRefundRequests[merchant];
        RefundRequestData[] memory requests = new RefundRequestData[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            requests[i] = refundRequests[keys[i].user][keys[i].depositNonce];
        }
        return requests;
    }

    /// @notice Cancel a refund request
    /// @param depositNonce The deposit nonce of the refund request to cancel
    /// @dev Only the user who created the request can cancel it
    ///      Request must be in Pending status
    function cancelRefundRequest(uint256 depositNonce) external {
        address user = msg.sender;
        
        RefundRequestData storage request = refundRequests[user][depositNonce];
        require(request.user != address(0), "Request does not exist");
        require(request.user == user, "Not request owner");
        require(request.status == RequestStatus.Pending, "Request not pending");
        
        // Update status to Cancelled
        request.status = RequestStatus.Cancelled;
        
        // Remove from indexing arrays
        _removeFromUserIndex(user, depositNonce);
        _removeFromMerchantIndex(request.merchantPayout, user, depositNonce);
        
        emit RefundRequestCancelled(user, depositNonce, msg.sender);
    }

    /// @notice Remove request from user's nonce array
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    function _removeFromUserIndex(address user, uint256 depositNonce) private {
        uint256[] storage nonces = userRefundRequestNonces[user];
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == depositNonce) {
                // Swap with last element and pop
                nonces[i] = nonces[nonces.length - 1];
                nonces.pop();
                break;
            }
        }
    }

    /// @notice Remove request from merchant's request array
    /// @param merchant The merchant payout address
    /// @param user The user address
    /// @param depositNonce The deposit nonce
    function _removeFromMerchantIndex(
        address merchant,
        address user,
        uint256 depositNonce
    ) private {
        RefundRequestKey[] storage keys = merchantRefundRequests[merchant];
        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i].user == user && keys[i].depositNonce == depositNonce) {
                // Swap with last element and pop
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }
    }
}

