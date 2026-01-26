// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MaliciousRecorder} from "./mocks/MaliciousRecorder.sol";

contract ReentrancyAttackTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public factory;
    MockERC20 public token;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MaliciousRecorder public maliciousRecorder;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
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
        factory = new PaymentOperatorFactory(
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    function _deployOperatorWithMaliciousRecorder(MaliciousRecorder.AttackType attackType, uint8 recorderSlot)
        internal
        returns (PaymentOperator)
    {
        maliciousRecorder = new MaliciousRecorder(attackType);

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            authorizeCondition: address(0),
            authorizeRecorder: recorderSlot == 0 ? address(maliciousRecorder) : address(0),
            chargeCondition: address(0),
            chargeRecorder: recorderSlot == 1 ? address(maliciousRecorder) : address(0),
            releaseCondition: address(0),
            releaseRecorder: recorderSlot == 2 ? address(maliciousRecorder) : address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: recorderSlot == 3 ? address(maliciousRecorder) : address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: recorderSlot == 4 ? address(maliciousRecorder) : address(0)
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
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: _operator,
            salt: uint256(keccak256(abi.encodePacked(_operator, payer, receiver, block.timestamp)))
        });
    }

    function test_ReentrancyOnAuthorize_SameFunction() public {
        operator = _deployOperatorWithMaliciousRecorder(MaliciousRecorder.AttackType.REENTER_SAME_FUNCTION, 0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        bytes32 hash = escrow.getHash(paymentInfo);
        (bool hasCollected, uint256 capturableAmount, uint256 refundableAmount) = escrow.paymentState(hash);

        // ✅ FIXED: Malicious recorder attack is now BLOCKED
        // PaymentOperator now has nonReentrant guards on all functions
        // The recorder attempted to call release() but was blocked by reentrancy guard
        assertTrue(hasCollected);
        assertEq(capturableAmount, PAYMENT_AMOUNT); // Attack blocked, still capturable
        assertEq(refundableAmount, 0); // Not refundable
        assertEq(maliciousRecorder.reentrancyCount(), 1); // Recorder still executed
    }

    function test_ReentrancyOnRelease_SameFunction() public {
        operator = _deployOperatorWithMaliciousRecorder(MaliciousRecorder.AttackType.REENTER_SAME_FUNCTION, 2);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(operator));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        uint256 receiverBalanceAfter = token.balanceOf(receiver);

        uint256 expectedFee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;
        uint256 expectedReceiverAmount = PAYMENT_AMOUNT - expectedFee;

        assertEq(receiverBalanceAfter - receiverBalanceBefore, expectedReceiverAmount);
        assertEq(maliciousRecorder.reentrancyCount(), 1);
    }
}
