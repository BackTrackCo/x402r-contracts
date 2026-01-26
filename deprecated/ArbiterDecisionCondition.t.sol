// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {ConditionNotMet} from "../src/commerce-payments/operator/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";

// Condition combinators
import {ICondition} from "../src/commerce-payments/conditions/ICondition.sol";
import {OrCondition} from "../src/commerce-payments/conditions/combinators/OrCondition.sol";
import {PayerCondition} from "../src/commerce-payments/conditions/access/PayerCondition.sol";
import {ArbiterCondition} from "../src/commerce-payments/conditions/access/ArbiterCondition.sol";
import {ReceiverCondition} from "../src/commerce-payments/conditions/access/ReceiverCondition.sol";

/**
 * @title ArbiterDecisionConditionTest
 * @notice Tests the arbiter decision pattern using condition combinators
 * @dev Release condition: payer OR arbiter can release
 *      Refund in escrow condition: receiver OR arbiter can refund
 */
contract ArbiterDecisionConditionTest is Test {
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;

    // Conditions
    OrCondition public releaseCondition; // payer OR arbiter
    OrCondition public refundCondition; // receiver OR arbiter

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();

        // Deploy atomic conditions
        PayerCondition payerCond = new PayerCondition();
        ArbiterCondition arbiterCond = new ArbiterCondition();
        ReceiverCondition receiverCond = new ReceiverCondition();

        // Create release condition: payer OR arbiter
        ICondition[] memory releaseConditions = new ICondition[](2);
        releaseConditions[0] = payerCond;
        releaseConditions[1] = arbiterCond;
        releaseCondition = new OrCondition(releaseConditions);

        // Create refund condition: receiver OR arbiter
        ICondition[] memory refundConditions = new ICondition[](2);
        refundConditions[0] = receiverCond;
        refundConditions[1] = arbiterCond;
        refundCondition = new OrCondition(refundConditions);

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        // Deploy operator with arbiter decision conditions
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0), // anyone can authorize
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition), // payer OR arbiter
            releaseRecorder: address(0),
            refundInEscrowCondition: address(refundCondition), // receiver OR arbiter
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0), // anyone
            refundPostEscrowRecorder: address(0)
        });
        operator = ArbitrationOperator(operatorFactory.deployOperator(config));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);

        vm.prank(receiver);
        token.approve(address(escrow), type(uint256).max);
    }

    // ============ Helper Functions ============

    function _createPaymentInfo() internal view returns (MockEscrow.PaymentInfo memory) {
        return MockEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _toAuthCapturePaymentInfo(MockEscrow.PaymentInfo memory mockInfo)
        internal
        pure
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: mockInfo.operator,
            payer: mockInfo.payer,
            receiver: mockInfo.receiver,
            token: mockInfo.token,
            maxAmount: mockInfo.maxAmount,
            preApprovalExpiry: mockInfo.preApprovalExpiry,
            authorizationExpiry: mockInfo.authorizationExpiry,
            refundExpiry: mockInfo.refundExpiry,
            minFeeBps: mockInfo.minFeeBps,
            maxFeeBps: mockInfo.maxFeeBps,
            feeReceiver: mockInfo.feeReceiver,
            salt: mockInfo.salt
        });
    }

    function _authorizeDirectly() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        // Authorize directly through operator
        operator.authorize(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo));
    }

    // ============ Release Tests ============

    function test_Release_RevertsIfNotArbiterOrPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Non-arbiter and non-payer cannot release
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // Random address cannot release
        vm.prank(address(0x1234));
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsForArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Arbiter can release
        vm.prank(arbiter);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsForPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Payer can release
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Refund In Escrow Tests ============

    function test_RefundInEscrow_RevertsIfNotReceiverOrArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Payer cannot refund
        vm.prank(payer);
        vm.expectRevert(ConditionNotMet.selector);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        // Random address cannot refund
        vm.prank(address(0x1234));
        vm.expectRevert(ConditionNotMet.selector);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_RefundInEscrow_SucceedsForReceiver() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Receiver can refund
        vm.prank(receiver);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_RefundInEscrow_SucceedsForArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Arbiter can refund
        vm.prank(arbiter);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    // ============ Direct Condition Tests ============

    function test_Condition_ReleaseReturnsFalse_ForNonPayerOrArbiter() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return false for non-payer and non-arbiter
        assertFalse(releaseCondition.check(authInfo, receiver));
        assertFalse(releaseCondition.check(authInfo, address(0x1234)));
    }

    function test_Condition_ReleaseReturnsTrue_ForPayer() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return true for payer
        assertTrue(releaseCondition.check(authInfo, payer));
    }

    function test_Condition_ReleaseReturnsTrue_ForArbiter() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return true for arbiter
        assertTrue(releaseCondition.check(authInfo, arbiter));
    }

    function test_Condition_RefundReturnsFalse_ForPayer() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return false for payer (only receiver or arbiter can refund)
        assertFalse(refundCondition.check(authInfo, payer));
    }

    function test_Condition_RefundReturnsTrue_ForReceiver() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return true for receiver
        assertTrue(refundCondition.check(authInfo, receiver));
    }

    function test_Condition_RefundReturnsTrue_ForArbiter() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Should return true for arbiter
        assertTrue(refundCondition.check(authInfo, arbiter));
    }
}
