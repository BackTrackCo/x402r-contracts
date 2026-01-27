// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {StaticAddressCondition} from "../src/conditions/StaticAddressCondition.sol";
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
        operatorFactory = new PaymentOperatorFactory(
            address(escrow), address(protocolFeeConfig), owner
        );

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

        // Deploy refund request contract
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
        refundRequest.requestRefund(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        bytes32 expectedHash = escrow.getHash(paymentInfo);

        assertEq(data.paymentInfoHash, expectedHash);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_RequestRefund_RevertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo);
    }

    function test_ApproveRefund_ByDesignatedAddress_InEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Designated address approves the refund request
        vm.prank(designatedAddress);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        // Now execute the actual refund through the operator
        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(designatedAddress);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_ApproveRefund_ByReceiver_InEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Receiver approves the refund request
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
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
        refundRequest.requestRefund(paymentInfo);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Cancelled));
    }

    function test_DenyRefund_ByDesignatedAddress() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(designatedAddress);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Denied);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_DenyRefund_ByReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Denied);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_ApproveRefund_PostEscrow_OnlyReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow state)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Receiver can approve post-escrow
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
    }

    function test_ApproveRefund_PostEscrow_DesignatedAddressCannotApprove() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow state)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Designated address cannot approve post-escrow (only receiver can)
        vm.prank(designatedAddress);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);
    }

    function test_UpdateStatus_PostEscrow_RevertsIfNotReceiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Release payment (move to post-escrow)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Random address cannot approve post-escrow (only receiver can)
        address randomAddress = makeAddr("random");
        vm.prank(randomAddress);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);
    }

    function test_UpdateStatus_RevertsIfNotPending() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Approve once
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, RequestStatus.Approved);

        // Cannot update again
        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.updateStatus(paymentInfo, RequestStatus.Denied);
    }

    function test_CancelRefund_RevertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        vm.prank(receiver);
        vm.expectRevert();
        refundRequest.cancelRefundRequest(paymentInfo);
    }

    function test_RequestRefund_AllowsReRequestAfterCancel() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // First request
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        // Cancel it
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo);

        // Should be able to request again
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo);

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }
}
