// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MaliciousHook} from "./mocks/MaliciousHook.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";

contract ReentrancyAttackTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public factory;
    ProtocolFeeConfig public protocolFeeConfig;
    MockERC20 public token;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MaliciousHook public maliciousHook;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public payer;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        payer = makeAddr("payer");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    function _deployOperatorWithMaliciousHook(MaliciousHook.AttackType attackType, uint8 hookSlot)
        internal
        returns (PaymentOperator)
    {
        maliciousHook = new MaliciousHook(attackType);

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: hookSlot == 0 ? address(maliciousHook) : address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: hookSlot == 1 ? address(maliciousHook) : address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: hookSlot == 2 ? address(maliciousHook) : address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: hookSlot == 3 ? address(maliciousHook) : address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: hookSlot == 4 ? address(maliciousHook) : address(0)
        });

        return PaymentOperator(factory.deployOperator(config));
    }

    function _createPaymentInfo(address _operator) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: _operator,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: _operator,
            salt: uint256(keccak256(abi.encodePacked(_operator, payer, receiver, block.timestamp)))
        });
    }

    function test_ReentrancyOnAuthorize_SameFunction() public {
        operator = _deployOperatorWithMaliciousHook(MaliciousHook.AttackType.REENTER_SAME_FUNCTION, 0);
        maliciousHook.setTargetAction(MaliciousHook.TargetAction.AUTHORIZE);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        bytes32 hash = escrow.getHash(paymentInfo);
        (bool hasCollected, uint256 capturableAmount, uint256 refundableAmount) = escrow.paymentState(hash);

        assertTrue(hasCollected);
        assertEq(capturableAmount, PAYMENT_AMOUNT, "single authorize amount captured (reentry blocked)");
        assertEq(refundableAmount, 0);
        assertEq(maliciousHook.reentrancyCount(), 1);
        assertTrue(maliciousHook.reentrancyBlocked(), "nonReentrant must block re-authorize");
    }

    function test_ReentrancyOnCapture_SameFunction() public {
        operator = _deployOperatorWithMaliciousHook(MaliciousHook.AttackType.REENTER_SAME_FUNCTION, 2);
        maliciousHook.setTargetAction(MaliciousHook.TargetAction.CAPTURE);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        vm.prank(receiver);
        operator.capture(paymentInfo, PAYMENT_AMOUNT, "");
        uint256 receiverBalanceAfter = token.balanceOf(receiver);

        assertEq(receiverBalanceAfter - receiverBalanceBefore, PAYMENT_AMOUNT, "no double-capture");
        assertEq(maliciousHook.reentrancyCount(), 1);
        assertTrue(maliciousHook.reentrancyBlocked(), "nonReentrant must block re-capture");
    }

    function test_ReentrancyOnVoid_SameFunction() public {
        operator = _deployOperatorWithMaliciousHook(MaliciousHook.AttackType.REENTER_SAME_FUNCTION, 3);
        maliciousHook.setTargetAction(MaliciousHook.TargetAction.VOID);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 payerBalanceBefore = token.balanceOf(payer);
        operator.void(paymentInfo, "");
        uint256 payerBalanceAfter = token.balanceOf(payer);

        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT, "single void amount returned");
        assertEq(maliciousHook.reentrancyCount(), 1);
        assertTrue(maliciousHook.reentrancyBlocked(), "nonReentrant must block re-void");
    }

    function test_ReentrancyOnRefund_SameFunction() public {
        operator = _deployOperatorWithMaliciousHook(MaliciousHook.AttackType.REENTER_SAME_FUNCTION, 4);
        maliciousHook.setTargetAction(MaliciousHook.TargetAction.REFUND);

        // Set up: authorize, capture, then refund. Refund pulls from receiver via
        // ReceiverRefundCollector, which transfers from receiver's wallet.
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        operator.capture(paymentInfo, PAYMENT_AMOUNT, "");

        ReceiverRefundCollector refundCollector = new ReceiverRefundCollector(address(escrow));
        vm.prank(receiver);
        token.approve(address(refundCollector), type(uint256).max);

        operator.refund(paymentInfo, PAYMENT_AMOUNT, address(refundCollector), "");

        assertEq(maliciousHook.reentrancyCount(), 1);
        assertTrue(maliciousHook.reentrancyBlocked(), "nonReentrant must block re-refund");
    }

    function test_ReentrancyOnCharge_SameFunction() public {
        operator = _deployOperatorWithMaliciousHook(MaliciousHook.AttackType.REENTER_SAME_FUNCTION, 1);
        maliciousHook.setTargetAction(MaliciousHook.TargetAction.CHARGE);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        operator.charge(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        uint256 receiverBalanceAfter = token.balanceOf(receiver);

        assertEq(receiverBalanceAfter - receiverBalanceBefore, PAYMENT_AMOUNT, "no double-charge");
        assertEq(maliciousHook.reentrancyCount(), 1);
        assertTrue(maliciousHook.reentrancyBlocked(), "nonReentrant must block re-charge");
    }
}
