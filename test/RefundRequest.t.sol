// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {BaseTest} from "./Base.t.sol";
import {RefundRequest} from "../src/simple/main/requests/RefundRequest.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

contract RefundRequestTest is BaseTest {
    RefundRequest public refundRequest;
    
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1000 USDC
    string public constant TEST_IPFS_LINK = "QmTest123";
    
    function setUp() public override {
        super.setUp();
        refundRequest = new RefundRequest(address(escrow));
    }
    
    function test_RequestRefund() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(user, depositNonce);
        assertEq(request.user, user, "User should match");
        assertEq(request.depositNonce, depositNonce, "Deposit nonce should match");
        assertEq(request.ipfsLink, TEST_IPFS_LINK, "IPFS link should match");
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Pending), "Status should be Pending");
    }
    
    function test_RequestRefund_EmptyIPFSLink() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        vm.expectRevert("Empty IPFS link");
        refundRequest.requestRefund(depositNonce, "");
    }
    
    function test_RequestRefund_DepositDoesNotExist() public {
        vm.prank(user);
        vm.expectRevert("Deposit does not exist");
        refundRequest.requestRefund(999, TEST_IPFS_LINK);
    }
    
    function test_RequestRefund_RequestAlreadyExists() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(user);
        vm.expectRevert("Request already exists");
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
    }
    
    function test_GetRefundRequest() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(user, depositNonce);
        assertEq(request.user, user, "User should match");
        assertEq(request.depositNonce, depositNonce, "Deposit nonce should match");
        assertEq(request.ipfsLink, TEST_IPFS_LINK, "IPFS link should match");
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Pending), "Status should be Pending");
    }
    
    function test_GetRefundRequest_DoesNotExist() public {
        vm.expectRevert("Request does not exist");
        refundRequest.getRefundRequest(user, 999);
    }
    
    function test_UpdateStatus_Approved_ByMerchant() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(user, depositNonce);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Approved), "Status should be Approved");
    }
    
    function test_UpdateStatus_Denied_ByMerchant() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Denied);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(user, depositNonce);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Denied), "Status should be Denied");
    }
    
    function test_UpdateStatus_Approved_ByArbiter() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(defaultArbiter);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
        
        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(user, depositNonce);
        assertEq(uint8(request.status), uint8(RefundRequest.RequestStatus.Approved), "Status should be Approved");
    }
    
    function test_UpdateStatus_InvalidStatus() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(merchant);
        vm.expectRevert("Invalid status");
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Pending);
    }
    
    function test_UpdateStatus_RequestDoesNotExist() public {
        vm.prank(merchant);
        vm.expectRevert("Request does not exist");
        refundRequest.updateStatus(user, 999, RefundRequest.RequestStatus.Approved);
    }
    
    function test_UpdateStatus_RequestNotPending() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
        
        vm.prank(merchant);
        vm.expectRevert("Request not pending");
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Denied);
    }
    
    function test_UpdateStatus_NotMerchantOrArbiter() public {
        address unauthorized = address(0x9999);
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.prank(unauthorized);
        vm.expectRevert("Not merchant or arbiter");
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
    }
    
    function test_HasRefundRequest() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        assertFalse(refundRequest.hasRefundRequest(user, depositNonce), "Request should not exist initially");
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        assertTrue(refundRequest.hasRefundRequest(user, depositNonce), "Request should exist after creation");
    }
    
    function test_GetRefundRequestStatus() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Status should be Pending (0) for non-existent request
        assertEq(refundRequest.getRefundRequestStatus(user, depositNonce), 0, "Non-existent request should return Pending");
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        assertEq(refundRequest.getRefundRequestStatus(user, depositNonce), 0, "Status should be Pending");
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
        
        assertEq(refundRequest.getRefundRequestStatus(user, depositNonce), 1, "Status should be Approved");
        
        // Test with a new request
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce2 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce2, TEST_IPFS_LINK);
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce2, RefundRequest.RequestStatus.Denied);
        
        assertEq(refundRequest.getRefundRequestStatus(user, depositNonce2), 2, "Status should be Denied");
    }
    
    function test_MultipleUsers_MultipleDeposits() public {
        address user2 = address(0x2222);
        
        // User 1 deposit and request
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce1 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce1, "ipfs1");
        
        // User 2 deposit and request
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce2 = escrow.noteDeposit(user2, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user2);
        refundRequest.requestRefund(depositNonce2, "ipfs2");
        
        // Verify both requests exist independently
        RefundRequest.RefundRequestData memory request1 = refundRequest.getRefundRequest(user, depositNonce1);
        RefundRequest.RefundRequestData memory request2 = refundRequest.getRefundRequest(user2, depositNonce2);
        
        assertEq(request1.user, user, "User 1 should match");
        assertEq(request2.user, user2, "User 2 should match");
        assertEq(request1.ipfsLink, "ipfs1", "IPFS link 1 should match");
        assertEq(request2.ipfsLink, "ipfs2", "IPFS link 2 should match");
        
        // Update status independently
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce1, RefundRequest.RequestStatus.Approved);
        
        vm.prank(defaultArbiter);
        refundRequest.updateStatus(user2, depositNonce2, RefundRequest.RequestStatus.Denied);
        
        assertEq(uint8(refundRequest.getRefundRequest(user, depositNonce1).status), uint8(RefundRequest.RequestStatus.Approved), "Request 1 should be Approved");
        assertEq(uint8(refundRequest.getRefundRequest(user2, depositNonce2).status), uint8(RefundRequest.RequestStatus.Denied), "Request 2 should be Denied");
    }
    
    function test_Events_RefundRequested() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, true, false, false);
        emit RefundRequest.RefundRequested(user, depositNonce, TEST_IPFS_LINK);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
    }
    
    function test_Events_RefundRequestStatusUpdated() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        refundRequest.requestRefund(depositNonce, TEST_IPFS_LINK);
        
        vm.expectEmit(true, true, false, false);
        emit RefundRequest.RefundRequestStatusUpdated(
            user,
            depositNonce,
            RefundRequest.RequestStatus.Pending,
            RefundRequest.RequestStatus.Approved,
            merchant
        );
        
        vm.prank(merchant);
        refundRequest.updateStatus(user, depositNonce, RefundRequest.RequestStatus.Approved);
    }
}

