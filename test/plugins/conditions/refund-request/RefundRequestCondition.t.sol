// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RefundRequestCondition} from "../../../../src/plugins/conditions/refund-request/RefundRequestCondition.sol";
import {
    RefundRequestConditionFactory
} from "../../../../src/plugins/conditions/refund-request/RefundRequestConditionFactory.sol";
import {ICondition} from "../../../../src/plugins/conditions/ICondition.sol";
import {OrCondition} from "../../../../src/plugins/conditions/combinators/OrCondition.sol";
import {ReceiverCondition} from "../../../../src/plugins/conditions/access/ReceiverCondition.sol";
import {PaymentOperator} from "../../../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../../../src/plugins/fees/ProtocolFeeConfig.sol";
import {RequestStatus} from "../../../../src/plugins/conditions/refund-request/types/Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";

contract RefundRequestConditionTest is Test {
    RefundRequestCondition public refundRequest;
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

        // Deploy RefundRequestCondition with arbiter
        refundRequest = new RefundRequestCondition(arbiter);

        // Deploy operator with refundRequest as refund condition
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
            refundInEscrowCondition: address(refundRequest),
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

    function test_constructor_setsArbiter() public view {
        assertEq(refundRequest.ARBITER(), arbiter);
    }

    function test_constructor_zeroArbiterReverts() public {
        vm.expectRevert(RefundRequestCondition.ZeroArbiter.selector);
        new RefundRequestCondition(address(0));
    }

    // ============ requestRefund Tests ============

    function test_requestRefund_success() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.nonce, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_requestRefund_revertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert(RefundRequestCondition.NotPayer.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_requestRefund_revertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, 0, 0);
    }

    // ============ approve Tests ============

    function test_approve_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        // approvedRefundAmounts should be updated
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT));
    }

    function test_approve_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT));
    }

    function test_approve_notAuthorized() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert(RefundRequestCondition.NotArbiterOrReceiver.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_conditionCheck() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Before approval, check() should return false
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // After approval, check() should return true
        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_approve_cumulativeAmounts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Create two requests for same payment
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 4), 0);
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 4), 1);

        // Approve first
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 4));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 4));

        // Approve second — should accumulate
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 1, uint120(PAYMENT_AMOUNT / 4));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 2));

        // check() should pass for cumulative amount
        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT / 2, address(0)));
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_approve_requestMustExist() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_requestMustBePending() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Try to approve again — should revert (not pending)
        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_partialAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve only half the requested amount
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2));

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT / 2));

        // approvedRefundAmounts should reflect partial amount
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 2));

        // check() should pass for partial amount but fail for full
        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT / 2, address(0)));
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
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

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    // ============ ICondition.check() Tests ============

    function test_check_falseBeforeApproval() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_trueAfterApproval() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_amountBound() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2));

        // Approved half — requesting more should fail
        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT / 2, address(0)));
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ deny Tests ============

    function test_deny_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_deny_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        vm.expectRevert(RefundRequestCondition.NotArbiter.selector);
        refundRequest.deny(paymentInfo, 0);
    }

    function test_deny_noConditionUpdate() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // No approved amounts — check should still be false
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ refuse Tests ============

    function test_refuse_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    function test_refuse_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        vm.expectRevert(RefundRequestCondition.NotArbiter.selector);
        refundRequest.refuse(paymentInfo, 0);
    }

    function test_refuse_noConditionUpdate() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ cancel Tests ============

    function test_cancel_onlyPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Non-payer cannot cancel
        vm.prank(receiver);
        vm.expectRevert(RefundRequestCondition.NotPayer.selector);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Payer can cancel
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
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

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT / 2));

        // Cancel history preserved
        assertEq(refundRequest.getCancelCount(paymentInfo, 0), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0, 0), uint120(PAYMENT_AMOUNT));
    }

    // ============ E2E Tests ============

    function test_e2e_approveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Step 1: Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Step 2: Arbiter approves
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Step 3: check() now passes
        assertTrue(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Step 4: Execute the refund — anyone can call since check() passes
        uint256 payerBalanceBefore = token.balanceOf(payer);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_e2e_denyFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // No condition state — check fails
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_e2e_refuseFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
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

    // ============ revoke Tests ============

    function test_revoke_setsPendingAndDecrements() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.revoke(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.approvedAmount, 0);
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), 0);

        // check() should now return false
        assertFalse(refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_revoke_receiverAsApprover() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Receiver approves
        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Arbiter cannot revoke receiver's approval
        vm.prank(arbiter);
        vm.expectRevert(RefundRequestCondition.NotApprover.selector);
        refundRequest.revoke(paymentInfo, 0);

        // Receiver can revoke their own approval
        vm.prank(receiver);
        refundRequest.revoke(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), 0);
    }

    function test_revoke_onlyApprover() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter approves
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Receiver cannot revoke arbiter's approval
        vm.prank(receiver);
        vm.expectRevert(RefundRequestCondition.NotApprover.selector);
        refundRequest.revoke(paymentInfo, 0);

        // Payer cannot revoke
        vm.prank(payer);
        vm.expectRevert(RefundRequestCondition.NotApprover.selector);
        refundRequest.revoke(paymentInfo, 0);

        // Random address cannot revoke
        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert(RefundRequestCondition.NotApprover.selector);
        refundRequest.revoke(paymentInfo, 0);
    }

    function test_revoke_onlyApproved() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Can't revoke a Pending request
        vm.prank(arbiter);
        vm.expectRevert(RefundRequestCondition.RequestNotApproved.selector);
        refundRequest.revoke(paymentInfo, 0);
    }

    function test_revoke_thenReapprove() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve full amount
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Revoke
        vm.prank(arbiter);
        refundRequest.revoke(paymentInfo, 0);

        // Re-approve with partial amount
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2));

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT / 2));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 2));
    }

    function test_revoke_thenDeny() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.revoke(paymentInfo, 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_revoke_cumulativeAccounting() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Two requests, approve both
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 4), 0);
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 4), 1);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 4));
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 1, uint120(PAYMENT_AMOUNT / 4));
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 2));

        // Revoke only the first — cumulative should drop by that amount
        vm.prank(arbiter);
        refundRequest.revoke(paymentInfo, 0);
        assertEq(refundRequest.approvedRefundAmounts(paymentInfoHash), uint120(PAYMENT_AMOUNT / 4));
    }

    // ============ operatorNotZero Tests ============

    function test_requestRefund_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        paymentInfo.operator = address(0);

        vm.prank(payer);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_approve_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        paymentInfo.operator = address(0);
        vm.prank(arbiter);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_cancel_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        paymentInfo.operator = address(0);
        vm.prank(payer);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.cancelRefundRequest(paymentInfo, 0);
    }

    function test_deny_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        paymentInfo.operator = address(0);
        vm.prank(arbiter);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.deny(paymentInfo, 0);
    }

    function test_refuse_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        paymentInfo.operator = address(0);
        vm.prank(arbiter);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.refuse(paymentInfo, 0);
    }

    function test_check_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        paymentInfo.operator = address(0);
        vm.expectRevert(RefundRequestCondition.InvalidOperator.selector);
        refundRequest.check(paymentInfo, PAYMENT_AMOUNT, address(0));
    }

    // ============ RequestAlreadyExists Tests ============

    function test_requestRefund_revertsIfAlreadyExists() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Same nonce without cancelling — should revert
        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);
    }

    // ============ Terminal State Transition Tests ============

    function test_approve_revertsIfDenied() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    function test_approve_revertsIfRefused() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    // ============ Payer Approve Rejection Test ============

    function test_approve_revertsIfPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(payer);
        vm.expectRevert(RefundRequestCondition.NotArbiterOrReceiver.selector);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));
    }

    // ============ Pagination Boundary Tests ============

    function test_pagination_offsetBeyondTotal() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 100, 10);
        assertEq(total, 1);
        assertEq(keys.length, 0);
    }

    function test_pagination_zeroCount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 0);
        assertEq(total, 1);
        assertEq(keys.length, 0);
    }

    function test_pagination_receiverAndOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Receiver pagination
        (bytes32[] memory receiverKeys, uint256 receiverTotal) =
            refundRequest.getReceiverRefundRequests(receiver, 0, 10);
        assertEq(receiverTotal, 1);
        assertEq(receiverKeys.length, 1);

        // Operator pagination
        (bytes32[] memory operatorKeys, uint256 operatorTotal) =
            refundRequest.getOperatorRefundRequests(address(operator), 0, 10);
        assertEq(operatorTotal, 1);
        assertEq(operatorKeys.length, 1);
    }

    function test_singleIndexGetter_revertsOutOfBounds() public {
        vm.expectRevert(RefundRequestCondition.IndexOutOfBounds.selector);
        refundRequest.getPayerRefundRequest(payer, 0);

        vm.expectRevert(RefundRequestCondition.IndexOutOfBounds.selector);
        refundRequest.getReceiverRefundRequest(receiver, 0);

        vm.expectRevert(RefundRequestCondition.IndexOutOfBounds.selector);
        refundRequest.getOperatorRefundRequest(address(operator), 0);
    }

    // ============ Hash Security Tests ============

    function test_compositeKey_differentNonces() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes32 key0 = keccak256(abi.encodePacked(paymentInfoHash, uint256(0)));
        bytes32 key1 = keccak256(abi.encodePacked(paymentInfoHash, uint256(1)));
        bytes32 key2 = keccak256(abi.encodePacked(paymentInfoHash, uint256(type(uint256).max)));

        assertTrue(key0 != key1, "Nonce 0 and 1 must differ");
        assertTrue(key1 != key2, "Nonce 1 and max must differ");
        assertTrue(key0 != key2, "Nonce 0 and max must differ");
    }

    function test_multipleNonces_independentRequests() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 1);

        // Approve nonce 0
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // Nonce 0 is Approved
        RefundRequestCondition.RefundRequestData memory data0 = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data0.status), uint256(RequestStatus.Approved));

        // Nonce 1 is still Pending (independent state)
        RefundRequestCondition.RefundRequestData memory data1 = refundRequest.getRefundRequest(paymentInfo, 1);
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

/// @notice Tests RefundRequestCondition within OrCondition(ReceiverCondition, RefundRequestCondition)
/// — the marketplace operator condition tree.
contract RefundRequestConditionOrConditionTest is Test {
    RefundRequestCondition public refundRequest;
    ReceiverCondition public receiverCondition;
    OrCondition public orCondition;
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

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy conditions — mirroring marketplace preset
        refundRequest = new RefundRequestCondition(arbiter);
        receiverCondition = new ReceiverCondition();

        // OrCondition(receiver, refundRequestCondition)
        ICondition[] memory conditions = new ICondition[](2);
        conditions[0] = ICondition(address(receiverCondition));
        conditions[1] = ICondition(address(refundRequest));
        orCondition = new OrCondition(conditions);

        // Deploy operator with OrCondition as refundInEscrowCondition
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
            refundInEscrowCondition: address(orCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

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

    function test_e2e_arbiterApproveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter approves
        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // OrCondition.check() passes (refundRequestCondition has the approval)
        assertTrue(orCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Anyone can execute the refund
        uint256 payerBalanceBefore = token.balanceOf(payer);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_e2e_receiverApproveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Receiver approves (instead of arbiter)
        vm.prank(receiver);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT));

        // OrCondition.check() passes via refundRequestCondition
        assertTrue(orCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Execute refund
        uint256 payerBalanceBefore = token.balanceOf(payer);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_deny_throughOrCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_refuse_throughOrCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        RefundRequestCondition.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }
}

/// @notice Tests for RefundRequestConditionFactory
contract RefundRequestConditionFactoryTest is Test {
    RefundRequestConditionFactory public factory;

    function setUp() public {
        factory = new RefundRequestConditionFactory();
    }

    function test_deploy_deterministic() public {
        address arbiter = makeAddr("arbiter");

        // Compute address before deployment
        address predicted = factory.computeAddress(arbiter);

        // Deploy
        address deployed = factory.deploy(arbiter);

        // Should match
        assertEq(deployed, predicted);
        assertTrue(deployed != address(0));

        // Should be stored
        assertEq(factory.getDeployed(arbiter), deployed);
        assertEq(factory.deployments(factory.getKey(arbiter)), deployed);
    }

    function test_deploy_idempotent() public {
        address arbiter = makeAddr("arbiter");

        address first = factory.deploy(arbiter);
        address second = factory.deploy(arbiter);

        assertEq(first, second);
    }

    function test_deploy_differentArbiters() public {
        address arbiter1 = makeAddr("arbiter1");
        address arbiter2 = makeAddr("arbiter2");

        address deployed1 = factory.deploy(arbiter1);
        address deployed2 = factory.deploy(arbiter2);

        assertTrue(deployed1 != deployed2);

        // Each should set ARBITER correctly
        assertEq(RefundRequestCondition(deployed1).ARBITER(), arbiter1);
        assertEq(RefundRequestCondition(deployed2).ARBITER(), arbiter2);
    }

    function test_deploy_zeroArbiter() public {
        vm.expectRevert(RefundRequestConditionFactory.ZeroArbiter.selector);
        factory.deploy(address(0));
    }
}
