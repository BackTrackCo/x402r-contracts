// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RefundRequest} from "../../../src/requests/refund/RefundRequest.sol";
import {RefundRequestFactory} from "../../../src/requests/refund/RefundRequestFactory.sol";
import {IPreActionCondition} from "../../../src/plugins/pre-action-conditions/IPreActionCondition.sol";
import {
    StaticAddressPreActionCondition
} from "../../../src/plugins/pre-action-conditions/access/static-address/StaticAddressPreActionCondition.sol";
import {
    ReceiverPreActionCondition
} from "../../../src/plugins/pre-action-conditions/access/ReceiverPreActionCondition.sol";
import {OrPreActionCondition} from "../../../src/plugins/pre-action-conditions/combinators/OrPreActionCondition.sol";
import {PaymentOperator} from "../../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../../src/plugins/fees/ProtocolFeeConfig.sol";
import {RequestStatus} from "../../../src/requests/types/Types.sol";
import {InvalidOperator} from "../../../src/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract RefundRequestTest is Test {
    RefundRequest public refundRequest;
    OrPreActionCondition public voidPreActionCondition;
    StaticAddressPreActionCondition public arbiterCondition;
    ReceiverPreActionCondition public receiverCondition;
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

        // Build condition tree:
        // VOID_PRE_ACTION_CONDITION = Or(StaticAddressPreActionCondition(arbiter), ReceiverPreActionCondition)
        arbiterCondition = new StaticAddressPreActionCondition(arbiter);
        receiverCondition = new ReceiverPreActionCondition();
        IPreActionCondition[] memory refundPreActionConditions = new IPreActionCondition[](2);
        refundPreActionConditions[0] = IPreActionCondition(address(arbiterCondition));
        refundPreActionConditions[1] = IPreActionCondition(address(receiverCondition));
        voidPreActionCondition = new OrPreActionCondition(refundPreActionConditions);

        // Deploy operator with refundRequest as VOID_POST_ACTION_HOOK
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(voidPreActionCondition),
            voidPostActionHook: address(refundRequest),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
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
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.approvedAmount, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_requestRefund_revertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_requestRefund_revertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, 0);
    }

    function test_requestRefund_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0);

        vm.prank(payer);
        vm.expectRevert(InvalidOperator.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_requestRefund_revertsIfAlreadyExists() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    // ============ Approve via operator.void() Tests ============

    function test_approve_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Arbiter calls operator.void() which triggers record()
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        // Check request status
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        // Check funds returned to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_approve_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Receiver calls operator.void() which triggers record()
        vm.prank(receiver);
        operator.void(paymentInfo, "");

        // Check request status
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));

        // Check funds returned to payer
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_approve_fullAmountVoid() public {
        // void() always returns the full capturable amount — no partial semantics.
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_approve_revertsIfNotArbiterOrReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Payer cannot call void (not in VOID_PRE_ACTION_CONDITION)
        vm.prank(payer);
        vm.expectRevert();
        operator.void(paymentInfo, "");

        // Random address cannot approve
        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert();
        operator.void(paymentInfo, "");
    }

    function test_approve_revertsIfDenied() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Deny first
        vm.prank(arbiter);
        refundRequest.deny(paymentInfo);

        // void still succeeds (funds move) but record() is a no-op since request is denied
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        // Request status remains Denied (record() was a no-op)
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_approve_capsAtRequestedAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2));

        // Refund full amount — record() should cap at requested amount
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT / 2));
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
    }

    function test_approve_revertsIfZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0);

        vm.prank(arbiter);
        vm.expectRevert(InvalidOperator.selector);
        refundRequest.deny(paymentInfo);
    }

    // ============ Post-Escrow Tests ============

    function test_approve_revertsPostEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Release all funds (moves them out of escrow)
        operator.capture(paymentInfo, PAYMENT_AMOUNT, "");

        // void reverts — no capturable funds left
        vm.prank(arbiter);
        vm.expectRevert();
        operator.void(paymentInfo, "");
    }

    function test_approve_partialRelease_refundsRemaining() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        uint120 releaseAmount = uint120(PAYMENT_AMOUNT / 2);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, refundAmount);

        // Release half
        operator.capture(paymentInfo, uint256(releaseAmount), "");

        uint256 payerBalanceBefore = token.balanceOf(payer);

        // Approve refund — succeeds since refundAmount <= capturableAmount
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
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
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_deny_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotArbiter.selector);
        refundRequest.deny(paymentInfo);
    }

    // ============ refuse Tests ============

    function test_refuse_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    function test_refuse_receiverReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(receiver);
        vm.expectRevert(RefundRequest.NotArbiter.selector);
        refundRequest.refuse(paymentInfo);
    }

    // ============ isArbiter Tests ============

    function test_isArbiter_arbiterReturnsTrue() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        assertTrue(refundRequest.isArbiter(paymentInfo, arbiter));
    }

    function test_isArbiter_receiverReturnsFalse() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        assertFalse(refundRequest.isArbiter(paymentInfo, receiver));
    }

    function test_isArbiter_payerReturnsFalse() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        assertFalse(refundRequest.isArbiter(paymentInfo, payer));
    }

    function test_isArbiter_randomReturnsFalse() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        assertFalse(refundRequest.isArbiter(paymentInfo, makeAddr("random")));
    }

    // ============ cancel Tests ============

    function test_cancel_onlyPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Non-payer cannot cancel
        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.cancelRefundRequest(paymentInfo);

        // Payer can cancel
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Cancelled));
    }

    function test_cancel_preservesHistory() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        assertEq(refundRequest.getCancelCount(paymentInfo), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0), uint120(PAYMENT_AMOUNT));
    }

    function test_cancel_reRequest() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request, cancel
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        // Re-request with different amount
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2));

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT / 2));

        // Cancel history preserved
        assertEq(refundRequest.getCancelCount(paymentInfo), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0), uint120(PAYMENT_AMOUNT));
    }

    // ============ E2E Tests ============

    function test_e2e_directRefundBlocked() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Calling operator.void directly from a non-permitted caller should revert
        // because OrPreActionCondition(arbiter, receiver) only allows arbiter and receiver
        address random = makeAddr("random");
        vm.prank(random);
        vm.expectRevert();
        operator.void(paymentInfo, "");

        // Payer calling directly also blocked (not in VOID_PRE_ACTION_CONDITION)
        vm.prank(payer);
        vm.expectRevert();
        operator.void(paymentInfo, "");
    }

    function test_e2e_approveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Step 1: Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Step 2: Arbiter calls operator.void() (atomically refunds + records)
        uint256 payerBalanceBefore = token.balanceOf(payer);
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        // Step 3: Payer received funds
        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);

        // Step 4: Status is Approved
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
        assertEq(data.approvedAmount, uint120(PAYMENT_AMOUNT));
    }

    function test_e2e_denyFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo);

        // Status is Denied, no funds moved
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_e2e_refuseFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    // ============ Pagination Tests ============

    function test_pagination() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Create 1 refund request (one per payment, no nonce)
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        assertEq(refundRequest.payerRefundRequestCount(payer), 1);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 1);
        assertEq(keys.length, 1);
    }

    function test_pagination_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        assertEq(refundRequest.receiverRefundRequestCount(receiver), 1);

        (bytes32[] memory keys, uint256 total) = refundRequest.getReceiverRefundRequests(receiver, 0, 10);
        assertEq(total, 1);
        assertEq(keys.length, 1);
    }

    function test_pagination_operator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        assertEq(refundRequest.operatorRefundRequestCount(address(operator)), 1);

        (bytes32[] memory keys, uint256 total) = refundRequest.getOperatorRefundRequests(address(operator), 0, 10);
        assertEq(total, 1);
        assertEq(keys.length, 1);
    }

    function test_pagination_emptyResult() public view {
        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 0);
        assertEq(keys.length, 0);
    }

    // ============ View Function Tests ============

    function test_getPaymentInfo_reverseLookup() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        AuthCaptureEscrow.PaymentInfo memory stored = refundRequest.getPaymentInfo(paymentInfoHash);
        assertEq(stored.operator, paymentInfo.operator);
        assertEq(stored.payer, paymentInfo.payer);
        assertEq(stored.receiver, paymentInfo.receiver);
        assertEq(stored.token, paymentInfo.token);
        assertEq(stored.maxAmount, paymentInfo.maxAmount);
        assertEq(stored.salt, paymentInfo.salt);
    }

    // ============ record() No-Op Tests ============

    function test_record_noopIfNoRequest() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // void succeeds (funds move) even without a request — record() is a no-op
        vm.prank(arbiter);
        operator.void(paymentInfo, "");

        // No request exists, so hasRefundRequest returns false
        assertFalse(refundRequest.hasRefundRequest(paymentInfo));
    }

    function test_record_noopIfNotOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Call record() directly from non-operator — should be a no-op
        vm.prank(arbiter);
        refundRequest.run(paymentInfo, PAYMENT_AMOUNT, arbiter, "");

        // Status should still be Pending
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
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
