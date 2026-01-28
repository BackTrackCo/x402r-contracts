// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticAddressCondition} from "../src/plugins/conditions/access/StaticAddressCondition.sol";
import {RequestStatus} from "../src/requests/types/Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RefundRequestTest is Test {
    RefundRequest public refundRequest;
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    StaticAddressCondition public designatedAddressCondition;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public designatedAddress;
    address public payer;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        designatedAddress = makeAddr("designatedAddress");
        payer = makeAddr("payer");

        // Deploy real escrow
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");

        // Deploy PreApprovalPaymentCollector
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy designated address condition for refunds
        designatedAddressCondition = new StaticAddressCondition(designatedAddress);

        // Deploy protocol fee config (calculator=address(0) means no fees)
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);

        // Deploy operator factory
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        // Deploy operator with designated address condition for refunds
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(designatedAddressCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Deploy refund request contract (reads conditions from operator)
        refundRequest = new RefundRequest();

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);

        vm.prank(receiver);
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

        // Pre-approve payment with collector
        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // Authorize payment through operator
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        return paymentInfo;
    }

    // ============ Request Refund Tests ============

    function test_RequestRefund_Success() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        bytes32 expectedHash = escrow.getHash(paymentInfo);

        assertEq(data.paymentInfoHash, expectedHash);
        assertEq(data.nonce, 0);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_RequestRefund_RevertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_RequestRefund_RevertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, 0, 0);
    }

    function test_ApproveRefund_ByArbiter_InEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter can approve refund requests while in escrow
        vm.prank(designatedAddress);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
    }

    function test_ApproveRefund_ByReceiver_InEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Receiver approves the refund request
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        // Receiver cannot execute refund (only designated address can per condition)
        // But designated address can execute after receiver approval
        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(designatedAddress);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_CancelRefund_Success() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Cancelled));
    }

    function test_DenyRefund_ByArbiter_InEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter can deny refund requests while in escrow
        vm.prank(designatedAddress);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Denied);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_DenyRefund_ByReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Denied);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_ApproveRefund_PostEscrow_OnlyReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow state)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Receiver can approve post-escrow
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
    }

    function test_ApproveRefund_PostEscrow_DesignatedAddressCannotApprove() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow state)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Designated address cannot approve post-escrow (only receiver can)
        vm.prank(designatedAddress);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);
    }

    function test_UpdateStatus_PostEscrow_RevertsIfNotReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Random address cannot approve post-escrow (only receiver can)
        address randomAddress = makeAddr("random");
        vm.prank(randomAddress);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);
    }

    function test_UpdateStatus_RevertsIfNotPending() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve once
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        // Cannot update again
        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Denied);
    }

    function test_CancelRefund_RevertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.cancelRefundRequest(paymentInfo, 0);
    }

    function test_RequestRefund_AllowsReRequestAfterCancel() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // First request
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Cancel it
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Should be able to request again (same nonce, different amount)
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT / 2));
    }

    // ============ Multiple Nonce Tests ============

    function test_RequestRefund_MultipleNonces() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request refund for nonce 0
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        // Request refund for nonce 1 (separate charge)
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 4), 1);

        // Both exist independently
        RefundRequest.RefundRequestData memory data0 = refundRequest.getRefundRequest(paymentInfo, 0);
        RefundRequest.RefundRequestData memory data1 = refundRequest.getRefundRequest(paymentInfo, 1);

        assertEq(data0.amount, uint120(PAYMENT_AMOUNT / 2));
        assertEq(data0.nonce, 0);
        assertEq(data1.amount, uint120(PAYMENT_AMOUNT / 4));
        assertEq(data1.nonce, 1);

        // Approve nonce 0, deny nonce 1
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 1, RequestStatus.Denied);

        assertEq(uint256(refundRequest.getRefundRequest(paymentInfo, 0).status), uint256(RequestStatus.Approved));
        assertEq(uint256(refundRequest.getRefundRequest(paymentInfo, 1).status), uint256(RequestStatus.Denied));
    }

    function test_RequestRefund_DuplicateNonceReverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Same nonce again should revert
        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    // ============ Pagination Tests ============

    function test_PaginationPayerRefundRequests() public {
        // Create multiple refund requests with different nonces
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 5), i);
        }

        // Check count
        assertEq(refundRequest.payerRefundRequestCount(payer), 5, "Should have 5 requests");

        // Get first 3
        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 3);
        assertEq(total, 5, "Total should be 5");
        assertEq(keys.length, 3, "Should return 3 keys");

        // Get remaining 2
        (bytes32[] memory keys2, uint256 total2) = refundRequest.getPayerRefundRequests(payer, 3, 3);
        assertEq(total2, 5, "Total should still be 5");
        assertEq(keys2.length, 2, "Should return 2 keys");

        // No overlap
        for (uint256 i = 0; i < keys.length; i++) {
            for (uint256 j = 0; j < keys2.length; j++) {
                assertTrue(keys[i] != keys2[j], "Should have no overlap");
            }
        }
    }

    function test_PaginationReceiverRefundRequests() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 3), i);
        }

        assertEq(refundRequest.receiverRefundRequestCount(receiver), 3, "Should have 3 requests");

        (bytes32[] memory keys, uint256 total) = refundRequest.getReceiverRefundRequests(receiver, 0, 10);
        assertEq(total, 3, "Total should be 3");
        assertEq(keys.length, 3, "Should return 3 keys");
    }

    function test_PaginationOffsetBeyondTotal() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 10, 5);
        assertEq(total, 1, "Total should be 1");
        assertEq(keys.length, 0, "Should return empty array");
    }

    function test_PaginationCountExceedsRemaining() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 3), i);
        }

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 3, "Total should be 3");
        assertEq(keys.length, 3, "Should return 3 keys (not 10)");
    }

    function test_PaginationZeroCount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 0);
        assertEq(total, 1, "Total should be 1");
        assertEq(keys.length, 0, "Should return empty array for count=0");
    }

    function test_SingleRefundRequestByIndex() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        bytes32 payerKey = refundRequest.getPayerRefundRequest(payer, 0);
        bytes32 receiverKey = refundRequest.getReceiverRefundRequest(receiver, 0);

        assertTrue(payerKey != bytes32(0), "Payer key should not be zero");
        assertEq(payerKey, receiverKey, "Keys should match for same request");

        // Verify data via key lookup
        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(payerKey);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.nonce, 0);
    }

    function test_SingleRefundRequestByIndex_RevertsOutOfBounds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Index 1 is out of bounds (only index 0 exists)
        vm.expectRevert(RefundRequest.IndexOutOfBounds.selector);
        refundRequest.getPayerRefundRequest(payer, 1);

        vm.expectRevert(RefundRequest.IndexOutOfBounds.selector);
        refundRequest.getReceiverRefundRequest(receiver, 1);
    }
}
