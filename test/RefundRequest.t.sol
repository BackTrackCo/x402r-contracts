// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorAccess} from "../src/commerce-payments/operator/arbitration/ArbitrationOperatorAccess.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {RefundRequest} from "../src/commerce-payments/requests/refund/RefundRequest.sol";
import {RequestStatus} from "../src/commerce-payments/requests/types/Types.sol";
import {NotPayer, NotReceiver, NotReceiverOrArbiter} from "../src/commerce-payments/types/Errors.sol";
import {RequestAlreadyExists, RequestNotPending} from "../src/commerce-payments/requests/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";

contract RefundRequestTest is Test {
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public factory;
    RefundRequest public refundRequest;
    MockERC20 public token;
    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver; // merchant
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;



    // Events
    event RefundRequested(
        bytes32 indexed paymentInfoHash,
        address indexed payer,
        address indexed receiver
    );

    event RefundRequestStatusUpdated(
        bytes32 indexed paymentInfoHash,
        RequestStatus oldStatus,
        RequestStatus newStatus,
        address indexed updatedBy
    );

    event RefundRequestCancelled(
        bytes32 indexed paymentInfoHash,
        address indexed payer
    );

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        releaseCondition = new MockReleaseCondition();

        // Deploy factory and operator
        factory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );
        operator = ArbitrationOperator(factory.deployOperator(arbiter, address(releaseCondition)));

        // Deploy RefundRequest
        refundRequest = new RefundRequest(address(operator));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(receiver);
        token.approve(address(escrow), type(uint256).max);
    }

    // ============ Helper Functions ============

    function _createPaymentInfo() internal view returns (MockEscrow.PaymentInfo memory) {
        return MockEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days), // Will be overridden by operator
            minFeeBps: 0,
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(0),
            salt: 12345
        });
    }

    function _toAuthCapturePaymentInfo(MockEscrow.PaymentInfo memory mockInfo)
        internal
        pure
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: mockInfo.operator,
            payer: mockInfo.payer,
            receiver: mockInfo.receiver,
            token: mockInfo.token,
            maxAmount: mockInfo.maxAmount,
            preApprovalExpiry: mockInfo.preApprovalExpiry,
            authorizationExpiry: mockInfo.authorizationExpiry,
            refundExpiry: mockInfo.refundExpiry,
            minFeeBps: mockInfo.minFeeBps,
            maxFeeBps: mockInfo.maxFeeBps,
            feeReceiver: mockInfo.feeReceiver,
            salt: mockInfo.salt
        });
    }

    // Helper to get the actual enforced PaymentInfo that the operator uses
    function _getEnforcedPaymentInfo(MockEscrow.PaymentInfo memory original)
        internal
        view
        returns (MockEscrow.PaymentInfo memory)
    {
        MockEscrow.PaymentInfo memory enforced = original;
        enforced.authorizationExpiry = type(uint48).max;
        enforced.refundExpiry = type(uint48).max; // Operator overrides to satisfy base escrow validation
        enforced.feeReceiver = address(operator);

        // Always expect MAX_TOTAL_FEE_RATE
        enforced.minFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        enforced.maxFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        return enforced;
    }

    function _authorize() internal returns (bytes32) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
        // Get the enforced info which matches what the operator actually used
        MockEscrow.PaymentInfo memory enforcedInfo = _getEnforcedPaymentInfo(paymentInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);
        return paymentInfoHash;
    }

    function _authorizeAndRequest() internal returns (bytes32) {
        bytes32 paymentInfoHash = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfoHash);

        return paymentInfoHash;
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsOperator() public view {
        assertEq(address(refundRequest.OPERATOR()), address(operator));
    }

    // ============ Request Refund Tests ============

    function test_RequestRefund_Success() public {
        bytes32 paymentInfoHash = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfoHash);

        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(paymentInfoHash);
        assertEq(request.paymentInfoHash, paymentInfoHash);
        assertEq(uint8(request.status), uint8(RequestStatus.Pending));
    }

    function test_RequestRefund_RevertsOnNotPayer() public {
        bytes32 paymentInfoHash = _authorize();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        refundRequest.requestRefund(paymentInfoHash);
    }



    function test_RequestRefund_RevertsOnDuplicate() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(payer);
        vm.expectRevert(RequestAlreadyExists.selector);
        refundRequest.requestRefund(paymentInfoHash);
    }

    function test_RequestRefund_AllowsAfterCancel() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        // Cancel
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfoHash);

        // Request again
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfoHash);

        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequest(paymentInfoHash);
        assertEq(uint8(request.status), uint8(RequestStatus.Pending));
    }

    // ============ Update Status Tests ============

    function test_UpdateStatus_ApproveByReceiverInEscrow() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(receiver);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );

        assertEq(
            uint8(refundRequest.getRefundRequestStatus(paymentInfoHash)),
            uint8(RequestStatus.Approved)
        );
    }

    function test_UpdateStatus_ApproveByArbiterInEscrow() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(arbiter);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );

        assertEq(
            uint8(refundRequest.getRefundRequestStatus(paymentInfoHash)),
            uint8(RequestStatus.Approved)
        );
    }

    function test_UpdateStatus_DenyByReceiverInEscrow() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(receiver);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Denied
        );

        assertEq(
            uint8(refundRequest.getRefundRequestStatus(paymentInfoHash)),
            uint8(RequestStatus.Denied)
        );
    }

    function test_UpdateStatus_RevertsOnPayerInEscrow() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(payer);
        vm.expectRevert(NotReceiverOrArbiter.selector);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );
    }

    function test_UpdateStatus_ApproveByReceiverPostCapture() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        // Approve release condition and capture
        releaseCondition.approve(paymentInfoHash);
        vm.prank(receiver);
        operator.release(paymentInfoHash, PAYMENT_AMOUNT);

        // Now update status post capture
        vm.prank(receiver);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );

        assertEq(
            uint8(refundRequest.getRefundRequestStatus(paymentInfoHash)),
            uint8(RequestStatus.Approved)
        );
    }

    function test_UpdateStatus_RevertsOnArbiterPostCapture() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        // Approve release condition and capture
        releaseCondition.approve(paymentInfoHash);
        vm.prank(receiver);
        operator.release(paymentInfoHash, PAYMENT_AMOUNT);

        // Arbiter should not be able to update post-capture
        vm.prank(arbiter);
        vm.expectRevert(NotReceiver.selector);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );
    }

    // ============ Cancel Tests ============

    function test_CancelRefundRequest_Success() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfoHash);

        assertEq(
            uint8(refundRequest.getRefundRequestStatus(paymentInfoHash)),
            uint8(RequestStatus.Cancelled)
        );
    }

    function test_CancelRefundRequest_RevertsOnNotPayer() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        refundRequest.cancelRefundRequest(paymentInfoHash);
    }

    function test_CancelRefundRequest_RevertsOnNotPending() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        // Approve first
        vm.prank(receiver);
        refundRequest.updateStatus(
            paymentInfoHash,
            RequestStatus.Approved
        );

        // Try to cancel
        vm.prank(payer);
        vm.expectRevert(RequestNotPending.selector);
        refundRequest.cancelRefundRequest(paymentInfoHash);
    }

    // ============ View Functions Tests ============

    function test_HasRefundRequest() public {
        bytes32 paymentInfoHash = _authorize();

        assertFalse(refundRequest.hasRefundRequest(paymentInfoHash));

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfoHash);

        assertTrue(refundRequest.hasRefundRequest(paymentInfoHash));
    }

    function test_GetPayerRefundRequests() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        RefundRequest.RefundRequestData[] memory requests = refundRequest.getPayerRefundRequests(payer);
        assertEq(requests.length, 1);
        assertEq(requests[0].paymentInfoHash, paymentInfoHash);
    }

    function test_GetReceiverRefundRequests() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        RefundRequest.RefundRequestData[] memory requests = refundRequest.getReceiverRefundRequests(receiver);
        assertEq(requests.length, 1);
        assertEq(requests[0].paymentInfoHash, paymentInfoHash);
    }

    function test_GetArbiterRefundRequests_FiltersInEscrow() public {
        bytes32 paymentInfoHash = _authorizeAndRequest();

        // Should show in arbiter requests while in escrow
        RefundRequest.RefundRequestData[] memory requests = refundRequest.getArbiterRefundRequests(receiver);
        assertEq(requests.length, 1);

        // Approve and capture
        releaseCondition.approve(paymentInfoHash);
        vm.prank(receiver);
        operator.release(paymentInfoHash, PAYMENT_AMOUNT);

        // Should NOT show in arbiter requests after capture (post-escrow)
        requests = refundRequest.getArbiterRefundRequests(receiver);
        assertEq(requests.length, 0);
    }
}
