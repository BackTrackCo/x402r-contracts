// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {TokenCollector} from "commerce-payments/collectors/TokenCollector.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {EscrowPeriod} from "../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";

/**
 * @title ReceiverRefundCollectorTest
 * @notice Tests for ReceiverRefundCollector: pre-approval-based post-escrow refunds from receiver
 */
contract ReceiverRefundCollectorTest is Test {
    // Infrastructure
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public paymentCollector;
    ReceiverRefundCollector public refundCollector;
    MockERC20 public token;

    // Fee system
    ProtocolFeeConfig public protocolFeeConfig;
    StaticFeeCalculator public protocolCalc;
    StaticFeeCalculator public operatorCalc;

    // Escrow period
    EscrowPeriod public escrowPeriod;

    // Operator
    PaymentOperatorFactory public operatorFactory;
    PaymentOperator public operator;

    // Addresses
    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    // Constants
    uint256 public constant PROTOCOL_BPS = 25;
    uint256 public constant OPERATOR_BPS = 50;
    uint256 public constant TOTAL_BPS = PROTOCOL_BPS + OPERATOR_BPS;
    uint256 public constant ESCROW_PERIOD_DURATION = 7 days;
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
        paymentCollector = new PreApprovalPaymentCollector(address(escrow));
        refundCollector = new ReceiverRefundCollector(address(escrow));

        // Deploy fee calculators
        protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        operatorCalc = new StaticFeeCalculator(OPERATOR_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);

        // Deploy escrow period
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        address escrowPeriodAddr = escrowPeriodFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(0));
        escrowPeriod = EscrowPeriod(escrowPeriodAddr);

        // Deploy operator (no release condition for simplicity — warp past escrow period in tests)
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(escrowPeriod),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(escrowPeriod),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Fund accounts
        token.mint(payer, PAYMENT_AMOUNT * 10);
        token.mint(receiver, PAYMENT_AMOUNT * 10);
        vm.prank(payer);
        token.approve(address(paymentCollector), type(uint256).max);
    }

    // ============ Helpers ============

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

    /// @dev Authorize, warp past escrow period, release — returns net amount received by receiver
    function _authorizeAndRelease(AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 amount)
        internal
        returns (uint256 netAmount)
    {
        // Authorize
        vm.prank(payer);
        paymentCollector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, amount, address(paymentCollector), "");

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Release
        uint256 receiverBefore = token.balanceOf(receiver);
        vm.prank(receiver);
        operator.release(paymentInfo, amount);
        netAmount = token.balanceOf(receiver) - receiverBefore;
    }

    // ============ Tests ============

    function test_collectorType() public view {
        assertEq(
            uint256(refundCollector.collectorType()),
            uint256(TokenCollector.CollectorType.Refund),
            "Must be Refund type"
        );
    }

    function test_authCaptureEscrow() public view {
        assertEq(address(refundCollector.authCaptureEscrow()), address(escrow), "Escrow address must match");
    }

    function test_fullLifecycle_authorizeReleaseRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(1);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Receiver approves refund collector
        vm.prank(receiver);
        token.approve(address(refundCollector), netAmount);

        // Post-escrow refund succeeds
        uint256 payerBefore = token.balanceOf(payer);
        operator.refundPostEscrow(paymentInfo, netAmount, address(refundCollector), "");
        assertEq(token.balanceOf(payer) - payerBefore, netAmount, "Payer receives full refund");
    }

    function test_revert_noAllowance() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(2);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Do NOT approve refund collector — should revert
        vm.expectRevert();
        operator.refundPostEscrow(paymentInfo, netAmount, address(refundCollector), "");
    }

    function test_revert_insufficientAllowance() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(3);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Approve less than refund amount
        vm.prank(receiver);
        token.approve(address(refundCollector), netAmount / 2);

        // Refund for full amount should revert
        vm.expectRevert();
        operator.refundPostEscrow(paymentInfo, netAmount, address(refundCollector), "");
    }

    function test_partialRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(4);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        uint256 halfRefund = netAmount / 2;

        // Approve only half
        vm.prank(receiver);
        token.approve(address(refundCollector), halfRefund);

        // Partial refund succeeds
        uint256 payerBefore = token.balanceOf(payer);
        operator.refundPostEscrow(paymentInfo, halfRefund, address(refundCollector), "");
        assertEq(token.balanceOf(payer) - payerBefore, halfRefund, "Payer receives partial refund");
    }

    function test_revokeApproval() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(5);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Approve then revoke
        vm.startPrank(receiver);
        token.approve(address(refundCollector), netAmount);
        token.approve(address(refundCollector), 0);
        vm.stopPrank();

        // Refund should revert
        vm.expectRevert();
        operator.refundPostEscrow(paymentInfo, netAmount, address(refundCollector), "");
    }

    function test_multipleSequentialRefunds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(6);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        uint256 thirdRefund = netAmount / 3;

        // Approve full amount
        vm.prank(receiver);
        token.approve(address(refundCollector), netAmount);

        // First refund
        uint256 payerBefore = token.balanceOf(payer);
        operator.refundPostEscrow(paymentInfo, thirdRefund, address(refundCollector), "");
        assertEq(token.balanceOf(payer) - payerBefore, thirdRefund, "First refund correct");

        // Second refund
        payerBefore = token.balanceOf(payer);
        operator.refundPostEscrow(paymentInfo, thirdRefund, address(refundCollector), "");
        assertEq(token.balanceOf(payer) - payerBefore, thirdRefund, "Second refund correct");

        // Check allowance decremented correctly
        uint256 remaining = token.allowance(receiver, address(refundCollector));
        assertEq(remaining, netAmount - thirdRefund * 2, "Allowance decremented correctly");
    }

    function test_revert_afterRefundExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(7);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Approve
        vm.prank(receiver);
        token.approve(address(refundCollector), netAmount);

        // Warp past refund expiry
        vm.warp(paymentInfo.refundExpiry + 1);

        // Refund should revert (enforced by escrow)
        vm.expectRevert();
        operator.refundPostEscrow(paymentInfo, netAmount, address(refundCollector), "");
    }

    function test_revert_exceedsCapturedAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(8);
        uint256 netAmount = _authorizeAndRelease(paymentInfo, PAYMENT_AMOUNT);

        // Approve more than captured
        vm.prank(receiver);
        token.approve(address(refundCollector), type(uint256).max);

        // Refund more than captured should revert (enforced by escrow)
        bytes32 hash = escrow.getHash(paymentInfo);
        (,, uint120 refundable) = escrow.paymentState(hash);
        vm.expectRevert();
        operator.refundPostEscrow(paymentInfo, uint256(refundable) + 1, address(refundCollector), "");
    }

    function test_revert_calledByNonEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(9);
        address tokenStore = makeAddr("tokenStore");

        vm.expectRevert(abi.encodeWithSelector(TokenCollector.OnlyAuthCaptureEscrow.selector));
        refundCollector.collectTokens(paymentInfo, tokenStore, 1000, "");
    }
}
