// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RefundRequest} from "../../../src/requests/refund/RefundRequest.sol";
import {RefundRequestFactory} from "../../../src/requests/refund/RefundRequestFactory.sol";
import {StaticAddressCondition} from "../../../src/plugins/conditions/access/static-address/StaticAddressCondition.sol";
import {PaymentOperator} from "../../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../../src/plugins/fees/ProtocolFeeConfig.sol";
import {RequestStatus} from "../../../src/requests/types/Types.sol";
import {RequestNotPending, ApproveAmountExceedsRequest} from "../../../src/requests/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract RefundRequestTest is Test {
    RefundRequest public refundRequest;
    StaticAddressCondition public staticCondition;
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public payer;
    address public arbiter;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        payer = makeAddr("payer");
        arbiter = makeAddr("arbiter");

        // Core infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy RefundRequest with arbiter
        refundRequest = new RefundRequest(arbiter);

        // Deploy StaticAddressCondition pointing to refundRequest
        staticCondition = new StaticAddressCondition(address(refundRequest));

        // Deploy operator with staticCondition as refund condition
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(staticCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    function _createPaymentInfo() internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(0),
            maxFeeBps: uint16(0),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _authorize() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        return paymentInfo;
    }

    // ============ Constructor Tests ============

    function test_constructor_zeroArbiter() public {
        vm.expectRevert(RefundRequest.ZeroArbiter.selector);
        new RefundRequest(address(0));
    }

    function test_constructor_setsArbiter() public view {
        assertEq(refundRequest.ARBITER(), arbiter);
    }

    // ============ requestRefund Tests ============

    function test_requestRefund_success() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.nonce, 0);
        assertEq(data.approvedAmount, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_requestRefund_revertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotPayer.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_requestRefund_revertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, 0, 0);
    }

    function test_requestRefund_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0);

        vm.prank(payer);
        vm.expectRevert(RefundRequest.InvalidOperator.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_requestRefund_revertsIfAlreadyExists() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    // ============ approve Tests ============

    function test_approve_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Check request status
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        // Check funds returned to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_approve_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Check request status
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        // Check funds returned to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_approve_partialAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 halfAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, halfAmount);

        // Check partial approval
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, halfAmount);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));

        // Check only partial amount returned to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT / 2);
    }

    function test_approve_revertsIfNotArbiterOrReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Payer cannot approve
        vm.prank(payer);
        vm.expectRevert(RefundRequest.NotArbiterOrReceiver.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Random address cannot approve
        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert(RefundRequest.NotArbiterOrReceiver.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_revertsIfDenied() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Deny first
        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // Cannot approve a denied request
        vm.prank(arbiter);
        vm.expectRevert(RequestNotPending.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_revertsIfFullyApproved() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve full amount
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Try again — exceeds request
        vm.prank(arbiter);
        vm.expectRevert(ApproveAmountExceedsRequest.selector);
        refundRequest.approve(paymentInfo, 0, 1);
    }

    function test_approve_revertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, 0);
    }

    function test_approve_revertsIfExceedsRequested() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 requestAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, requestAmount, 0);

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0);

        vm.prank(arbiter);
        vm.expectRevert(RefundRequest.InvalidOperator.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    // ============ Cumulative Top-Up Tests ============

    function test_approve_cumulativeTopUp_arbiterThenReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 firstAmount = uint120(PAYMENT_AMOUNT / 4);
        uint120 secondAmount = uint120(PAYMENT_AMOUNT / 4);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Arbiter approves first chunk
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, firstAmount);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.approvedAmount, firstAmount);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        // Receiver tops up second chunk
        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, secondAmount);

        data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.approvedAmount, firstAmount + secondAmount);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        // Total refunded to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, uint256(firstAmount) + uint256(secondAmount));
    }

    function test_approve_cumulativeTopUp_receiverThenArbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 firstAmount = uint120(PAYMENT_AMOUNT / 5);
        uint120 secondAmount = uint120(PAYMENT_AMOUNT / 5 * 3);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Receiver approves first
        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, firstAmount);

        // Arbiter tops up
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, secondAmount);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.approvedAmount, firstAmount + secondAmount);

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, uint256(firstAmount) + uint256(secondAmount));
    }

    function test_approve_cumulativeTopUp_threeIncrements() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 chunk = uint120(PAYMENT_AMOUNT / 4);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, chunk);
        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, chunk);
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, chunk);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.approvedAmount, chunk * 3);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, uint256(chunk) * 3);
    }

    function test_approve_cumulativeTopUp_revertsIfExceedsTotal() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 halfAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve half
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, halfAmount);

        // Try to approve more than remaining — should revert
        vm.prank(receiver);
        vm.expectRevert(ApproveAmountExceedsRequest.selector);
        refundRequest.approve(paymentInfo, 0, halfAmount + 1);
    }

    // ============ Post-Escrow Tests ============

    function test_approve_revertsPostEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Release all funds (moves them out of escrow)
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // Approve reverts — no capturable funds left
        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_partialRelease_refundsRemaining() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 releaseAmount = uint120(PAYMENT_AMOUNT / 2);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, refundAmount, 0);

        // Release half — half remains in escrow
        operator.release(paymentInfo, uint256(releaseAmount));

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Approve refund — succeeds since refundAmount <= capturableAmount
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, refundAmount);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, refundAmount);

        // Payer received funds
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, uint256(refundAmount));
    }

    // ============ deny Tests ============

    function test_deny_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_deny_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotArbiter.selector);
        refundRequest.deny(paymentInfo, 0);
    }

    // ============ refuse Tests ============

    function test_refuse_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    function test_refuse_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotArbiter.selector);
        refundRequest.refuse(paymentInfo, 0);
    }

    // ============ cancel Tests ============

    function test_cancel_onlyPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Non-payer cannot cancel
        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotPayer.selector);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Payer can cancel
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Cancelled));
    }

    function test_cancel_preservesHistory() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        assertEq(refundRequest.getCancelCount(paymentInfo, 0), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0, 0), uint120(PAYMENT_AMOUNT));
    }

    function test_cancel_reRequest() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request, cancel
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Re-request with different amount
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT / 2));

        // Cancel history preserved
        assertEq(refundRequest.getCancelCount(paymentInfo, 0), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0, 0), uint120(PAYMENT_AMOUNT));
    }

    // ============ E2E Tests ============

    function test_e2e_directRefundBlocked() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Calling operator.refundInEscrow directly (not through RefundRequest) should revert
        // because StaticAddressCondition only allows refundRequest as caller
        vm.expectRevert();
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Arbiter calling directly also blocked
        vm.prank(arbiter);
        vm.expectRevert();
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Receiver calling directly also blocked
        vm.prank(receiver);
        vm.expectRevert();
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_e2e_approveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Step 1: Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Step 2: Arbiter approves (atomically refunds)
        uint256 payerBalanceBefore = token.balanceOf(payer);
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Step 3: Payer received funds
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);

        // Step 4: Status is Approved
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));
    }

    function test_e2e_denyFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // Status is Denied, no funds moved
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_e2e_refuseFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    // ============ Pagination Tests ============

    function test_pagination() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Create 3 refund requests
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 3), i);
        }

        assertEq(refundRequest.payerRefundRequestCount(payer), 3);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 3);
        assertEq(keys.length, 3);
    }

    function test_pagination_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        assertEq(refundRequest.receiverRefundRequestCount(receiver), 1);

        (bytes32[] memory keys, uint256 total) = refundRequest.getReceiverRefundRequests(receiver, 0, 10);
        assertEq(total, 1);
        assertEq(keys.length, 1);
    }

    function test_pagination_operator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        assertEq(refundRequest.operatorRefundRequestCount(address(operator)), 1);

        (bytes32[] memory keys, uint256 total) = refundRequest.getOperatorRefundRequests(address(operator), 0, 10);
        assertEq(total, 1);
        assertEq(keys.length, 1);
    }

    function test_pagination_offset() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 5), i);
        }

        // Get items 2-3 (offset=2, count=2)
        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 2, 2);
        assertEq(total, 5);
        assertEq(keys.length, 2);
    }

    function test_pagination_emptyResult() public view {
        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 0);
        assertEq(keys.length, 0);
    }

    // ============ Hash Security Tests ============

    function test_compositeKey_differentNonces() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes32 key0 = keccak256(abi.encodePacked(paymentInfoHash, uint256(0)));
        bytes32 key1 = keccak256(abi.encodePacked(paymentInfoHash, uint256(1)));

        assertTrue(key0 != key1, "Nonce 0 and 1 must differ");
    }

    function test_multipleNonces_independentRequests() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 1);

        // Approve nonce 0
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2));

        // Nonce 0 is Approved
        RefundRequest.RefundRequestData memory data0 = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data0.status), uint256(RequestStatus.Approved));

        // Nonce 1 is still Pending (independent state)
        RefundRequest.RefundRequestData memory data1 = refundRequest.getRefundRequest(paymentInfo, 1);
        assertEq(uint256(data1.status), uint256(RequestStatus.Pending));
    }

    function test_getPaymentInfo_reverseLookup() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        AuthCaptureEscrow.PaymentInfo memory stored = refundRequest.getPaymentInfo(paymentInfoHash);
        assertEq(stored.operator, paymentInfo.operator);
        assertEq(stored.payer, paymentInfo.payer);
        assertEq(stored.receiver, paymentInfo.receiver);
        assertEq(stored.token, paymentInfo.token);
        assertEq(stored.maxAmount, paymentInfo.maxAmount);
        assertEq(stored.salt, paymentInfo.salt);
    }
}

// ============ Factory Tests ============

contract RefundRequestFactoryTest is Test {
    RefundRequestFactory public factory;

    address public arbiter1;
    address public arbiter2;

    function setUp() public {
        factory = new RefundRequestFactory();
        arbiter1 = makeAddr("arbiter1");
        arbiter2 = makeAddr("arbiter2");
    }

    function test_deploy_deterministic() public {
        address predicted = factory.computeAddress(arbiter1);

        address deployed = factory.deploy(arbiter1);

        assertEq(deployed, predicted);
        assertEq(RefundRequest(deployed).ARBITER(), arbiter1);
    }

    function test_deploy_idempotent() public {
        address first = factory.deploy(arbiter1);
        address second = factory.deploy(arbiter1);

        assertEq(first, second);
    }

    function test_deploy_differentArbiters() public {
        address rr1 = factory.deploy(arbiter1);
        address rr2 = factory.deploy(arbiter2);

        assertTrue(rr1 != rr2);
        assertEq(RefundRequest(rr1).ARBITER(), arbiter1);
        assertEq(RefundRequest(rr2).ARBITER(), arbiter2);
    }

    function test_deploy_zeroArbiter() public {
        vm.expectRevert(RefundRequestFactory.ZeroArbiter.selector);
        factory.deploy(address(0));
    }

    function test_getDeployed_returnsZeroBeforeDeploy() public view {
        assertEq(factory.getDeployed(arbiter1), address(0));
    }

    function test_getDeployed_returnsAddressAfterDeploy() public {
        address deployed = factory.deploy(arbiter1);
        assertEq(factory.getDeployed(arbiter1), deployed);
    }

    function test_deploy_emitsEvent() public {
        address predicted = factory.computeAddress(arbiter1);

        vm.expectEmit(true, true, false, false);
        emit RefundRequestFactory.RefundRequestDeployed(predicted, arbiter1);

        factory.deploy(arbiter1);
    }
}
