// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RefundRequest} from "../src/commerce-payments/requests/refund/RefundRequest.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {RequestStatus} from "../src/commerce-payments/requests/types/Types.sol";
import {
    NotReceiver,
    NotPayer,
    NotReceiverOrArbiter,
    InvalidOperator
} from "../src/commerce-payments/types/Errors.sol";
import {
    RequestAlreadyExists,
    RequestDoesNotExist,
    RequestNotPending
} from "../src/commerce-payments/requests/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";


contract RefundRequestTest is Test {
    RefundRequest public refundRequest;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;

    // Events
    event RefundRequested(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer, address indexed receiver);
    event RefundRequestStatusUpdated(AuthCaptureEscrow.PaymentInfo paymentInfo, RequestStatus oldStatus, RequestStatus newStatus, address indexed updatedBy);
    event RefundRequestCancelled(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer);

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

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator with release condition as BEFORE_HOOK
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(releaseCondition), // BEFORE_HOOK: requires approval
            address(0)                  // AFTER_HOOK: no-op
        ));

        // Deploy refund request (no factory needed - singleton)
        refundRequest = new RefundRequest();

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
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
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

    function _authorize() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo));
    }

    // ============ Request Refund Tests ============

    function test_RequestRefund_Success() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.expectEmit(true, true, false, true);
        emit RefundRequested(paymentInfo, payer, receiver);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        assertTrue(refundRequest.hasRefundRequest(paymentInfo));
        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Pending));
    }

    function test_RequestRefund_RevertsOnNotPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        refundRequest.requestRefund(paymentInfo);
    }

    function test_RequestRefund_RevertsOnDuplicate() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(payer);
        vm.expectRevert(RequestAlreadyExists.selector);
        refundRequest.requestRefund(paymentInfo);
    }

    function test_RequestRefund_AllowsAfterCancel() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        // Should allow re-request after cancel
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Pending));
    }

    // ============ Update Status Tests ============

    function test_UpdateStatus_ApproveByReceiverInEscrow() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Approved));
    }

    function test_UpdateStatus_ApproveByArbiterInEscrow() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(arbiter);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Approved));
    }

    function test_UpdateStatus_DenyByReceiverInEscrow() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Denied);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Denied));
    }

    function test_UpdateStatus_RevertsOnPayerInEscrow() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(payer);
        vm.expectRevert(NotReceiverOrArbiter.selector);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);
    }

    function test_UpdateStatus_ApproveByReceiverPostCapture() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        // Approve the release and call release on operator (pull model)
        releaseCondition.approvePayment(paymentInfo);
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Receiver can still approve post-capture
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Approved));
    }

    function test_UpdateStatus_RevertsOnArbiterPostCapture() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        // Approve the release and call release on operator (pull model)
        releaseCondition.approvePayment(paymentInfo);
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Arbiter cannot approve post-capture
        vm.prank(arbiter);
        vm.expectRevert(NotReceiver.selector);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);
    }

    // ============ Cancel Tests ============

    function test_CancelRefundRequest_Success() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.expectEmit(true, false, false, true);
        emit RefundRequestCancelled(paymentInfo, payer);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        assertEq(uint8(refundRequest.getRefundRequestStatus(paymentInfo)), uint8(RequestStatus.Cancelled));
    }

    function test_CancelRefundRequest_RevertsOnNotPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        refundRequest.cancelRefundRequest(paymentInfo);
    }

    function test_CancelRefundRequest_RevertsOnNotPending() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        vm.prank(payer);
        vm.expectRevert(RequestNotPending.selector);
        refundRequest.cancelRefundRequest(paymentInfo);
    }

    // ============ View Function Tests ============

    function test_HasRefundRequest() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        assertFalse(refundRequest.hasRefundRequest(paymentInfo));

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        assertTrue(refundRequest.hasRefundRequest(paymentInfo));
    }

    function test_GetPayerRefundRequestHashes() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        bytes32[] memory hashes = refundRequest.getPayerRefundRequestHashes(payer);
        assertEq(hashes.length, 1);
        assertEq(hashes[0], paymentInfoHash);
    }

    function test_GetReceiverRefundRequestHashes() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        bytes32[] memory hashes = refundRequest.getReceiverRefundRequestHashes(receiver);
        assertEq(hashes.length, 1);
        assertEq(hashes[0], paymentInfoHash);
    }

    function test_GetRefundRequestByHash() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        RefundRequest.RefundRequestData memory request = refundRequest.getRefundRequestByHash(paymentInfoHash);
        assertEq(request.paymentInfoHash, paymentInfoHash);
        assertEq(uint8(request.status), uint8(RequestStatus.Pending));
    }
}
