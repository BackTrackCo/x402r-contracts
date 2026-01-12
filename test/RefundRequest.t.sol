// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {RefundRequest} from "../src/commerce-payments/requests/RefundRequest.sol";
import {ArbiterationOperator} from "../src/commerce-payments/operator/ArbiterationOperator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";

contract RefundRequestTest is Test {
    RefundRequest public refundRequest;
    ArbiterationOperator public operator;
    MockERC20 public token;
    MockEscrow public escrow;
    
    address public owner;
    address public merchant;
    address public arbiter;
    address public payer;
    
    uint256 public constant REFUND_DELAY = 7 days;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;
    bytes32 public authorizationId;
    
    function setUp() public {
        owner = address(this);
        merchant = makeAddr("merchant");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");
        
        // Deploy contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        
        operator = new ArbiterationOperator(
            address(escrow),
            makeAddr("protocolFeeRecipient"),
            50, // 0.5 bps
            25  // 25%
        );
        
        refundRequest = new RefundRequest(address(operator));
        
        // Setup
        token.mint(payer, 1000000 * 10**18);
        operator.registerMerchant(merchant, arbiter, REFUND_DELAY);
        
        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
        
        // Create authorization
        vm.prank(payer);
        authorizationId = operator.authorize(
            payer,
            merchant,
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor_SetsOperator() public {
        assertEq(address(refundRequest.OPERATOR()), address(operator));
    }
    
    function test_Constructor_RevertsOnZeroOperator() public {
        vm.expectRevert("Zero operator");
        new RefundRequest(address(0));
    }
    
    // ============ Request Refund Tests ============
    
    function test_RequestRefund_Success() public {
        string memory ipfsLink = "QmTest123";
        
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit RefundRequest.RefundRequested(authorizationId, payer, ipfsLink);
        
        refundRequest.requestRefund(authorizationId, ipfsLink);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(request.payer, payer);
        assertEq(request.authorizationId, authorizationId);
        assertEq(request.merchantPayout, merchant);
        assertEq(request.ipfsLink, ipfsLink);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Pending));
        assertEq(request.originalAmount, PAYMENT_AMOUNT);
    }
    
    function test_RequestRefund_RevertsOnEmptyIPFSLink() public {
        vm.prank(payer);
        vm.expectRevert("Empty IPFS link");
        refundRequest.requestRefund(authorizationId, "");
    }
    
    function test_RequestRefund_RevertsOnNonExistentAuthorization() public {
        vm.prank(payer);
        // getPayer reverts with ZeroAddress() when authorization doesn't exist
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        refundRequest.requestRefund(bytes32(uint256(123)), "QmTest123");
    }
    
    function test_RequestRefund_RevertsOnNotPayer() public {
        vm.expectRevert("Only payer can request refund");
        refundRequest.requestRefund(authorizationId, "QmTest123");
    }
    
    function test_RequestRefund_RevertsOnDuplicateRequest() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(payer);
        vm.expectRevert("Request already exists");
        refundRequest.requestRefund(authorizationId, "QmTest456");
    }
    
    function test_RequestRefund_AllowsReRequestAfterCancellation() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(payer);
        refundRequest.cancelRefundRequest(authorizationId);
        
        // Should be able to request again
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest456");
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(request.ipfsLink, "QmTest456");
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Pending));
    }
    
    // ============ Update Status Tests ============
    
    function test_UpdateStatus_Approve_PreCapture_ByMerchant() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        vm.expectEmit(true, false, false, true);
        emit RefundRequest.RefundRequestStatusUpdated(
            authorizationId,
            RefundRequest.RequestStatus.Pending,
            RefundRequest.RequestStatus.Approved,
            merchant
        );
        
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Approved));
    }
    
    function test_UpdateStatus_Approve_PreCapture_ByArbiter() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(arbiter);
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Approved));
    }
    
    function test_UpdateStatus_Approve_PostCapture_ByMerchant() public {
        // Capture first
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        vm.prank(merchant);
        operator.capture(authorizationId, PAYMENT_AMOUNT);
        
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        refundRequest.updateStatusPostEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Approved));
    }
    
    function test_UpdateStatus_Approve_PostCapture_RevertsOnArbiter() public {
        // Capture first
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        vm.prank(merchant);
        operator.capture(authorizationId, PAYMENT_AMOUNT);
        
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.updateStatusPostEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
    }
    
    function test_UpdateStatus_Deny_PreCapture() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Denied);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Denied));
    }
    
    function test_UpdateStatus_Deny_RevertsOnFullyRefunded() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        // Fully refund
        vm.prank(merchant);
        operator.refundInEscrow(authorizationId, PAYMENT_AMOUNT);
        
        vm.prank(merchant);
        vm.expectRevert("Cannot deny: authorization already fully refunded");
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Denied);
    }
    
    function test_UpdateStatus_RevertsOnInvalidStatus() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        vm.expectRevert("Invalid status");
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Cancelled);
    }
    
    function test_UpdateStatus_RevertsOnNonExistentRequest() public {
        vm.expectRevert();
        refundRequest.updateStatusInEscrow(bytes32(uint256(123)), RefundRequest.RequestStatus.Approved);
    }
    
    function test_UpdateStatus_RevertsOnNotPending() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        
        vm.prank(merchant);
        vm.expectRevert("Request not pending");
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Denied);
    }
    
    // ============ Cancel Refund Request Tests ============
    
    function test_CancelRefundRequest_Success() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit RefundRequest.RefundRequestCancelled(authorizationId, payer, payer);
        
        refundRequest.cancelRefundRequest(authorizationId);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(authorizationId);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Cancelled));
    }
    
    function test_CancelRefundRequest_RevertsOnNotOwner() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.expectRevert("Not request owner");
        refundRequest.cancelRefundRequest(authorizationId);
    }
    
    function test_CancelRefundRequest_RevertsOnNonExistent() public {
        vm.prank(payer);
        vm.expectRevert("Request does not exist");
        refundRequest.cancelRefundRequest(bytes32(uint256(123)));
    }
    
    function test_CancelRefundRequest_RevertsOnNotPending() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        vm.prank(merchant);
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        
        vm.prank(payer);
        vm.expectRevert("Request not pending");
        refundRequest.cancelRefundRequest(authorizationId);
    }
    
    // ============ View Functions Tests ============
    
    function test_HasRefundRequest() public {
        assertFalse(refundRequest.hasRefundRequest(authorizationId));
        
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        assertTrue(refundRequest.hasRefundRequest(authorizationId));
    }
    
    function test_GetRefundRequestStatus() public {
        assertEq(refundRequest.getRefundRequestStatus(authorizationId), 0); // Pending (default)
        
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        assertEq(refundRequest.getRefundRequestStatus(authorizationId), 0); // Pending
        
        vm.prank(merchant);
        refundRequest.updateStatusInEscrow(authorizationId, RefundRequest.RequestStatus.Approved);
        assertEq(refundRequest.getRefundRequestStatus(authorizationId), 1); // Approved
    }
    
    function test_GetPayerRefundRequests() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        RefundRequest.RefundRequestData[] memory requests = refundRequest.getPayerRefundRequests(payer);
        assertEq(requests.length, 1);
        assertEq(requests[0].authorizationId, authorizationId);
    }
    
    function test_GetMerchantRefundRequests() public {
        vm.prank(payer);
        refundRequest.requestRefund(authorizationId, "QmTest123");
        
        RefundRequest.RefundRequestData[] memory requests = refundRequest.getMerchantRefundRequests(merchant);
        assertEq(requests.length, 1);
        assertEq(requests[0].authorizationId, authorizationId);
    }
    
    function test_GetRefundRequest_RevertsOnNonExistent() public {
        vm.expectRevert("Request does not exist");
        refundRequest.getRefundRequest(bytes32(uint256(123)));
    }
}

