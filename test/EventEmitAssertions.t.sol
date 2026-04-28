// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    AuthorizeExecuted,
    ChargeExecuted,
    CaptureExecuted,
    VoidExecuted,
    RefundExecuted,
    FeesDistributed
} from "../src/operator/types/Events.sol";
import {OperatorDeployed} from "../src/operator/types/Events.sol";

/// @title EventEmitAssertions
/// @notice Pins the renamed event signatures + indexed-arg layout. Catches future
///         drift in field order, indexed flags, or arg names that would silently
///         break SDK / subgraph consumers without these assertions.
contract EventEmitAssertionsTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public factory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PROTOCOL_BPS = 25;
    uint256 public constant OPERATOR_BPS = 50;
    uint256 public constant TOTAL_BPS = PROTOCOL_BPS + OPERATOR_BPS;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        StaticFeeCalculator protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        StaticFeeCalculator operatorCalc = new StaticFeeCalculator(OPERATOR_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);
        factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
        operator = PaymentOperator(factory.deployOperator(config));

        token.mint(payer, PAYMENT_AMOUNT * 10);
        token.mint(receiver, PAYMENT_AMOUNT * 10);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    function _paymentInfo(uint256 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: uint16(TOTAL_BPS),
            maxFeeBps: uint16(TOTAL_BPS),
            feeReceiver: address(operator),
            salt: salt
        });
    }

    // ============ Action events ============

    function test_authorize_emitsAuthorizeExecuted() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(1);
        vm.prank(payer);
        collector.preApprove(pi);

        bytes32 hash = escrow.getHash(pi);

        vm.expectEmit(true, true, true, true, address(operator));
        emit AuthorizeExecuted(pi, hash, payer, receiver, PAYMENT_AMOUNT);
        operator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
    }

    function test_charge_emitsChargeExecuted() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(2);
        vm.prank(payer);
        collector.preApprove(pi);

        bytes32 hash = escrow.getHash(pi);

        vm.expectEmit(true, true, true, true, address(operator));
        emit ChargeExecuted(pi, hash, payer, receiver, PAYMENT_AMOUNT);
        operator.charge(pi, PAYMENT_AMOUNT, address(collector), "");
    }

    function test_capture_emitsCaptureExecuted() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(3);
        vm.prank(payer);
        collector.preApprove(pi);
        operator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        bytes32 hash = escrow.getHash(pi);

        vm.expectEmit(true, true, true, true, address(operator));
        emit CaptureExecuted(pi, hash, payer, receiver, PAYMENT_AMOUNT);
        vm.prank(receiver);
        operator.capture(pi, PAYMENT_AMOUNT, "");
    }

    function test_void_emitsVoidExecuted_noAmount() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(4);
        vm.prank(payer);
        collector.preApprove(pi);
        operator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        bytes32 hash = escrow.getHash(pi);

        // VoidExecuted intentionally omits the amount field — full-void semantics.
        vm.expectEmit(true, true, true, true, address(operator));
        emit VoidExecuted(pi, hash, payer, receiver);
        operator.void(pi, "");
    }

    function test_refund_emitsRefundExecuted() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(5);
        vm.prank(payer);
        collector.preApprove(pi);
        operator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(receiver);
        operator.capture(pi, PAYMENT_AMOUNT, "");

        ReceiverRefundCollector refundCollector = new ReceiverRefundCollector(address(escrow));
        vm.prank(receiver);
        token.approve(address(refundCollector), type(uint256).max);

        bytes32 hash = escrow.getHash(pi);
        uint256 partialRefund = PAYMENT_AMOUNT / 2;

        vm.expectEmit(true, true, true, true, address(operator));
        emit RefundExecuted(pi, hash, payer, receiver, partialRefund);
        operator.refund(pi, partialRefund, address(refundCollector), "");
    }

    // ============ Fee distribution event ============

    function test_distributeFees_emitsFeesDistributed_operatorAmount() public {
        // Capture a payment so fees accumulate.
        AuthCaptureEscrow.PaymentInfo memory pi = _paymentInfo(6);
        vm.prank(payer);
        collector.preApprove(pi);
        operator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(receiver);
        operator.capture(pi, PAYMENT_AMOUNT, "");

        uint256 totalFee = (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        uint256 protocolShare = (PAYMENT_AMOUNT * PROTOCOL_BPS) / 10000;
        uint256 operatorShare = totalFee - protocolShare;

        // Pin the field order: (token, protocolAmount, operatorAmount).
        // The third arg name was renamed from arbiterAmount -> operatorAmount; the
        // value here corresponds to what's actually transferred to FEE_RECEIVER, so
        // a swap of the two amount fields would break this assertion.
        vm.expectEmit(true, false, false, true, address(operator));
        emit FeesDistributed(address(token), protocolShare, operatorShare);
        operator.distributeFees(address(token));
    }

    // ============ Factory event ============

    function test_deployOperator_emitsOperatorDeployed_feeReceiver() public {
        // Use a fresh config so the operator hasn't been deployed yet.
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: makeAddr("freshFeeReceiver"),
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });

        // Compute the deterministic address before deployment so we can pin it in the event.
        address expected = factory.computeAddress(config);

        // Pin the field order: (operator, deployer, feeReceiver). All three indexed.
        // The third arg name was renamed from feeRecipient -> feeReceiver.
        vm.expectEmit(true, true, true, false, address(factory));
        emit OperatorDeployed(expected, address(this), makeAddr("freshFeeReceiver"));
        factory.deployOperator(config);
    }
}
