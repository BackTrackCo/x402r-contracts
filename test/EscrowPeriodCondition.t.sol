// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {EscrowPeriodCondition} from "../src/conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodConditionFactory} from "../src/conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {EscrowPeriodRecorder} from "../src/conditions/escrow-period/EscrowPeriodRecorder.sol";
import {FreezePolicy} from "../src/conditions/escrow-period/freeze-policy/FreezePolicy.sol";
import {PayerCondition} from "../src/conditions/access/PayerCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EscrowPeriodConditionTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    EscrowPeriodCondition public escrowCondition;
    EscrowPeriodRecorder public recorder;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant ESCROW_PERIOD = 7 days;
    uint256 public constant FREEZE_DURATION = 3 days;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy via factory
        EscrowPeriodConditionFactory conditionFactory = new EscrowPeriodConditionFactory();
        PayerCondition payerCondition = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCondition), address(payerCondition), FREEZE_DURATION);
        (address recorderAddr, address conditionAddr) = conditionFactory.deploy(ESCROW_PERIOD, address(freezePolicy));
        recorder = EscrowPeriodRecorder(recorderAddr);
        escrowCondition = EscrowPeriodCondition(conditionAddr);

        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(recorder),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(escrowCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        token.mint(payer, PAYMENT_AMOUNT * 10);
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
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function test_ReleaseBlockedDuringEscrowPeriod() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(receiver);
        vm.expectRevert();
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_ReleaseAllowedAfterEscrowPeriod() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        assertTrue(token.balanceOf(receiver) > 0);
    }

    function test_PayerCanFreezePayment() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        recorder.freeze(paymentInfo);

        assertTrue(recorder.isFrozen(paymentInfo));
    }
}
