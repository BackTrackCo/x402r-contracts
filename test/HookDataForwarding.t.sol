// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockDataPreActionCondition} from "./mocks/MockDataPreActionCondition.sol";
import {MockDataPostActionHook} from "./mocks/MockDataPostActionHook.sol";

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
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

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

    // ============ void: data forwarded to condition ============

    function test_void_nonEmptyData_reachesCondition() public {
        // Deploy MockDataPreActionCondition that requires MAGIC in data
        MockDataPreActionCondition dataCondition = new MockDataPreActionCondition(MAGIC);
        MockDataPostActionHook dataRecorder = new MockDataPostActionHook();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(dataCondition),
            voidPostActionHook: address(dataRecorder),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 111);

        // Authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // void with empty data should REVERT (condition requires magic)
        vm.expectRevert();
        operator.void(paymentInfo, "");

        // void with wrong magic should REVERT
        vm.expectRevert();
        operator.void(paymentInfo, abi.encode(bytes32(uint256(999))));

        // void with correct magic should SUCCEED
        bytes memory hookData = abi.encode(MAGIC);
        uint256 payerBefore = token.balanceOf(payer);
        operator.void(paymentInfo, hookData);
        uint256 payerAfter = token.balanceOf(payer);

        // Verify funds returned (full void returns the entire authorized amount)
        assertEq(payerAfter - payerBefore, PAYMENT_AMOUNT, "Payer should receive refund");

        // Verify recorder received the data
        assertEq(dataRecorder.recordCount(), 1, "Recorder should be called once");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder should receive the hook data");
    }

    // ============ authorize: dual-purpose collectorData reaches condition AND collector ============

    function test_authorize_collectorData_reachesConditionAndRecorder() public {
        // Deploy MockDataPreActionCondition on the AUTHORIZE_PRE_ACTION_CONDITION slot
        MockDataPreActionCondition dataCondition = new MockDataPreActionCondition(MAGIC);
        MockDataPostActionHook dataRecorder = new MockDataPostActionHook();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(dataCondition),
            authorizePostActionHook: address(dataRecorder),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
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
        MockDataPreActionCondition dataCondition = new MockDataPreActionCondition(MAGIC);
        MockDataPostActionHook dataRecorder = new MockDataPostActionHook();

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(dataCondition),
            capturePostActionHook: address(dataRecorder),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
        PaymentOperator operator = PaymentOperator(operatorFactory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator), 333);

        // Authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Release with empty data — should REVERT
        vm.expectRevert();
        operator.capture(paymentInfo, PAYMENT_AMOUNT, "");

        // Release with correct data — should SUCCEED
        bytes memory hookData = abi.encode(MAGIC);
        operator.capture(paymentInfo, PAYMENT_AMOUNT, hookData);

        assertEq(dataRecorder.recordCount(), 1, "Recorder called on release");
        assertEq(dataRecorder.lastReceivedData(), hookData, "Recorder receives release data");
    }
}
