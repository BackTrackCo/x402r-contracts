// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockDataCondition} from "./mocks/MockDataCondition.sol";
import {MockDataRecorder} from "./mocks/MockDataRecorder.sol";

import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";

/**
 * @title HookDataForwardingTest
 * @notice Verifies that non-empty `data` is forwarded end-to-end from callers
 *         through PaymentOperator to conditions and recorders.
 */
contract HookDataForwardingTest is Test {
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    ProtocolFeeConfig public protocolFeeConfig;
    PaymentOperatorFactory public operatorFactory;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;
    address public arbiter;

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;
    bytes32 public constant MAGIC = keccak256("x402r.test.magic");

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig), false);

        token.mint(payer, PAYMENT_AMOUNT * 10);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);

        token.mint(receiver, PAYMENT_AMOUNT * 10);
        vm.prank(receiver);
        token.approve(address(collector), type(uint256).max);
    }

    function _createPaymentInfo(address op, uint256 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: op,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: op,
            salt: salt
        });
    }

    // ============ refundInEscrow: data forwarded to condition ============

    function test_refundInEscrow_nonEmptyData_reachesCondition() public {
        // Deploy MockDataCondition that requires MAGIC in data
        MockDataCondition dataCondition = new MockDataCondition(MAGIC);
        MockDataRecorder dataRecorder = new MockDataRecorder();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(dataCondition),
            refundInEscrowRecorder: address(dataRecorder),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 111);

        // Authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // refundInEscrow with empty data should REVERT (condition requires magic)
        vm.expectRevert();
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT / 2), "");

        // refundInEscrow with wrong magic should REVERT
        vm.expectRevert();
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT / 2), abi.encode(bytes32(uint256(999))));

        // refundInEscrow with correct magic should SUCCEED
        bytes memory hookData = abi.encode(MAGIC);
        uint256 payerBefore = token.balanceOf(payer);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT / 2), hookData);
        uint256 payerAfter = token.balanceOf(payer);

        // Verify funds returned
        assertEq(payerAfter - payerBefore, PAYMENT_AMOUNT / 2, "Payer should receive refund");

        // Verify recorder received the data
        assertEq(dataRecorder.recordCount(), 1, "Recorder should be called once");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder should receive the hook data");
    }

    // ============ RefundRequest.approve: data forwarded to condition via operator ============

    function test_refundRequest_approve_nonEmptyData_reachesCondition() public {
        // Deploy MockDataCondition that requires MAGIC in data
        MockDataCondition dataCondition = new MockDataCondition(MAGIC);
        MockDataRecorder dataRecorder = new MockDataRecorder();

        // Deploy RefundRequest
        RefundRequest refundRequest = new RefundRequest(arbiter, false);

        // Deploy StaticAddressCondition allowing BOTH RefundRequest AND any caller with correct data
        // We use an AndCondition-like approach: the condition just checks data, and we also need
        // StaticAddressCondition for access control. But for simplicity, let's just use the
        // MockDataCondition directly (it validates the data, but anyone can call).
        // In production you'd compose with StaticAddressCondition via AndCondition.

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(dataCondition),
            refundInEscrowRecorder: address(dataRecorder),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 222);

        // Authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Request refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve with empty data — should REVERT because condition requires MAGIC
        vm.prank(arbiter);
        vm.expectRevert();
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2), "");

        // Approve with correct MAGIC data — should SUCCEED
        bytes memory hookData = abi.encode(MAGIC);
        uint256 payerBefore = token.balanceOf(payer);

        vm.prank(arbiter);
        refundRequest.approve(paymentInfo, 0, uint120(PAYMENT_AMOUNT / 2), hookData);

        uint256 payerAfter = token.balanceOf(payer);
        assertEq(payerAfter - payerBefore, PAYMENT_AMOUNT / 2, "Payer should receive refund via approve");

        // Verify recorder received the data end-to-end through RefundRequest -> operator -> recorder
        assertEq(dataRecorder.recordCount(), 1, "Recorder should be called once");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder should receive hook data from approve");
    }

    // ============ authorize: dual-purpose collectorData reaches condition AND collector ============

    function test_authorize_collectorData_reachesConditionAndRecorder() public {
        // Deploy MockDataCondition on the AUTHORIZE_CONDITION slot
        MockDataCondition dataCondition = new MockDataCondition(MAGIC);
        MockDataRecorder dataRecorder = new MockDataRecorder();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(dataCondition),
            authorizeRecorder: address(dataRecorder),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 444);

        // Pre-approve so collector can pull funds
        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // authorize with empty collectorData should REVERT (condition requires magic)
        vm.expectRevert();
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // authorize with wrong magic should REVERT
        vm.expectRevert();
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), abi.encode(bytes32(uint256(999))));

        // authorize with correct magic as collectorData — should SUCCEED
        // This validates the dual-purpose design: the same bytes reach both
        // the collector (PreApprovalPaymentCollector ignores collectorData) AND the condition
        bytes memory hookData = abi.encode(MAGIC);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), hookData);

        // Verify authorization succeeded (funds moved to escrow)
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        (bool exists,,) = escrow.paymentState(paymentInfoHash);
        assertTrue(exists, "Payment should be authorized");

        // Verify recorder received the collectorData as hook data
        assertEq(dataRecorder.recordCount(), 1, "Recorder should be called once");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder should receive collectorData as hook data");
    }

    // ============ release: data forwarded to condition and recorder ============

    function test_release_nonEmptyData_reachesConditionAndRecorder() public {
        MockDataCondition dataCondition = new MockDataCondition(MAGIC);
        MockDataRecorder dataRecorder = new MockDataRecorder();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(dataCondition),
            releaseRecorder: address(dataRecorder),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 333);

        // Authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Release with empty data — should REVERT
        vm.expectRevert();
        operator.release(paymentInfo, PAYMENT_AMOUNT, "");

        // Release with correct data — should SUCCEED
        bytes memory hookData = abi.encode(MAGIC);
        operator.release(paymentInfo, PAYMENT_AMOUNT, hookData);

        assertEq(dataRecorder.recordCount(), 1, "Recorder called on release");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder receives release data");
    }
}
