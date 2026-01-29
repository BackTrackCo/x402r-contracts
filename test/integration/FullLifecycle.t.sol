// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {EscrowPeriod} from "../../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {Freeze} from "../../src/plugins/freeze/Freeze.sol";
import {FreezePolicy} from "../../src/plugins/freeze/freeze-policy/FreezePolicy.sol";
import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {AndCondition} from "../../src/plugins/conditions/combinators/AndCondition.sol";
import {PayerCondition} from "../../src/plugins/conditions/access/PayerCondition.sol";
import {RefundRequest} from "../../src/requests/refund/RefundRequest.sol";
import {RequestStatus} from "../../src/requests/types/Types.sol";
import {PaymentState} from "../../src/operator/types/Types.sol";

/**
 * @title FullLifecycleTest
 * @notice End-to-end integration tests exercising the full payment lifecycle:
 *         escrow, fees, freeze/unfreeze, release, refund request, and post-escrow refund.
 */
contract FullLifecycleTest is Test {
    // Infrastructure
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    // Fee system
    ProtocolFeeConfig public protocolFeeConfig;
    StaticFeeCalculator public protocolCalc;
    StaticFeeCalculator public operatorCalc;

    // Escrow period system
    EscrowPeriod public escrowPeriod;
    Freeze public freeze;
    AndCondition public releaseCondition;
    PayerCondition public payerCondition;
    FreezePolicy public freezePolicy;

    // Operator
    PaymentOperatorFactory public operatorFactory;
    PaymentOperator public operator;

    // Refund request
    RefundRequest public refundRequest;

    // Addresses
    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    // Constants
    uint256 public constant PROTOCOL_BPS = 25; // 0.25%
    uint256 public constant OPERATOR_BPS = 50; // 0.50%
    uint256 public constant TOTAL_BPS = PROTOCOL_BPS + OPERATOR_BPS;
    uint256 public constant ESCROW_PERIOD = 7 days;
    uint256 public constant FREEZE_DURATION = 3 days;
    uint256 public constant PAYMENT_AMOUNT = 100_000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        // Deploy infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy fee calculators
        protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        operatorCalc = new StaticFeeCalculator(OPERATOR_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);

        // Deploy escrow period via factory
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        payerCondition = new PayerCondition();
        freezePolicy = new FreezePolicy(address(payerCondition), address(payerCondition), FREEZE_DURATION);
        address escrowPeriodAddr = escrowPeriodFactory.deploy(ESCROW_PERIOD, bytes32(0));
        escrowPeriod = EscrowPeriod(escrowPeriodAddr);

        // Deploy freeze with escrow period constraint
        freeze = new Freeze(address(freezePolicy), address(escrowPeriod), address(escrow));

        // Compose escrow period + freeze into release condition
        ICondition[] memory conditions = new ICondition[](2);
        conditions[0] = ICondition(address(escrowPeriod));
        conditions[1] = ICondition(address(freeze));
        releaseCondition = new AndCondition(conditions);

        // Deploy operator with full configuration
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(escrowPeriod),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Deploy refund request contract
        refundRequest = new RefundRequest();

        // Fund accounts
        token.mint(payer, PAYMENT_AMOUNT * 10);
        token.mint(receiver, PAYMENT_AMOUNT * 10);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
        vm.prank(receiver);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Full 10-Step Lifecycle ============

    function test_FullLifecycle_AuthorizeToRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(12345);

        // --- Step 1: AUTHORIZE ---
        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.stopPrank();
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.InEscrow), "Step 1: Must be InEscrow");

        // --- Step 2: RELEASE BLOCKED (within escrow period) ---
        vm.prank(receiver);
        vm.expectRevert();
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // --- Step 3: FREEZE ---
        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo), "Step 3: Must be frozen");

        // --- Step 4: Warp past both freeze duration and escrow period ---
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // --- Step 5: Freeze expired, escrow period passed ---
        assertFalse(freeze.isFrozen(paymentInfo), "Step 5: Freeze should have expired");

        // --- Step 6: RELEASE ---
        uint256 receiverBefore = token.balanceOf(receiver);
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        uint256 expectedTotalFee = (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        uint256 expectedNetAmount = PAYMENT_AMOUNT - expectedTotalFee;
        assertEq(token.balanceOf(receiver) - receiverBefore, expectedNetAmount, "Step 6: Receiver gets net amount");

        state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.Released), "Step 6: Must be Released");

        // --- Step 7: FEE DISTRIBUTION ---
        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * PROTOCOL_BPS) / 10000;
        uint256 expectedOperatorFee = expectedTotalFee - expectedProtocolFee;

        operator.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Step 7: Protocol fee correct");
        assertEq(token.balanceOf(operatorFeeRecipient), expectedOperatorFee, "Step 7: Operator fee correct");

        // --- Step 8: REFUND REQUEST ---
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(expectedNetAmount), 0);

        RefundRequest.RefundRequestData memory reqData = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(reqData.status), uint256(RequestStatus.Pending), "Step 8: Request pending");

        // --- Step 9: APPROVE REFUND ---
        vm.prank(receiver);
        refundRequest.updateStatus(paymentInfo, 0, RequestStatus.Approved);

        reqData = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(reqData.status), uint256(RequestStatus.Approved), "Step 9: Request approved");

        // --- Step 10: Verify refund request state is tracked correctly ---
        assertEq(refundRequest.payerRefundRequestCount(payer), 1, "Step 10: Payer has 1 refund request");
        assertEq(refundRequest.receiverRefundRequestCount(receiver), 1, "Step 10: Receiver has 1 refund request");
        assertTrue(refundRequest.hasRefundRequest(paymentInfo, 0), "Step 10: Refund request exists");
    }

    // ============ Charge Direct Payment Lifecycle ============

    function test_LifecycleWithCharge() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(54321);

        uint256 receiverBefore = token.balanceOf(receiver);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.charge(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 expectedTotalFee = (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        uint256 expectedNetAmount = PAYMENT_AMOUNT - expectedTotalFee;

        // Receiver gets funds directly
        assertEq(token.balanceOf(receiver) - receiverBefore, expectedNetAmount, "Receiver gets net via charge");

        // Fees accumulated
        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * PROTOCOL_BPS) / 10000;
        assertEq(operator.accumulatedProtocolFees(address(token)), expectedProtocolFee, "Protocol fees tracked");

        // Distribute
        operator.distributeFees(address(token));
        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Protocol recipient paid");
    }

    // ============ Partial Refund In Escrow Lifecycle ============

    function test_LifecyclePartialRefundInEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(99999);

        // Authorize
        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.stopPrank();
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Partial refund (50%)
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);
        operator.refundInEscrow(paymentInfo, refundAmount);

        bytes32 hash = escrow.getHash(paymentInfo);
        (, uint120 capturable,) = escrow.paymentState(hash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount, "Capturable reduced by refund");

        // Still InEscrow
        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.InEscrow), "Still InEscrow after partial refund");

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Release remainder
        uint256 remainder = PAYMENT_AMOUNT - refundAmount;
        uint256 receiverBefore = token.balanceOf(receiver);
        vm.prank(receiver);
        operator.release(paymentInfo, remainder);

        uint256 expectedFee = (remainder * TOTAL_BPS) / 10000;
        uint256 expectedNet = remainder - expectedFee;
        assertEq(token.balanceOf(receiver) - receiverBefore, expectedNet, "Receiver gets remainder minus fees");
    }

    // ============ Helper Functions ============

    function _createPaymentInfo(uint256 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
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
}
