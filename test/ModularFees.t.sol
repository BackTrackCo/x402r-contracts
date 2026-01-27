// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/fees/StaticFeeCalculator.sol";
import {IFeeCalculator} from "../src/fees/IFeeCalculator.sol";

/**
 * @title ModularFeesTest
 * @notice Integration tests for the modular fee system
 * @dev Tests:
 *      - Dynamic fees with StaticFeeCalculator
 *      - Fee distribution (protocol tracked amount vs operator remainder)
 *      - Additive structure (protocol + operator)
 *      - Protocol fee tracking
 *      - address(0) calculator scenarios (no protocol fee, no operator fee, both zero)
 */
contract ModularFeesTest is Test {
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PAYMENT_AMOUNT = 1000000; // 1M wei for easy bps math

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        token.mint(payer, 100000000 * 10 ** 18);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Both Calculators Active (Additive) ============

    function test_AdditiveFees_BothActive() public {
        uint256 protocolBps = 25; // 0.25%
        uint256 operatorBps = 50; // 0.50%
        uint256 totalBps = protocolBps + operatorBps; // 75 bps = 0.75%

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        // Authorize and release
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), totalBps);
        _authorizePayment(op, paymentInfo);
        op.release(paymentInfo, PAYMENT_AMOUNT);

        // Calculate expected fees
        uint256 expectedTotalFee = (PAYMENT_AMOUNT * totalBps) / 10000; // 75
        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * protocolBps) / 10000; // 25
        uint256 expectedOperatorFee = expectedTotalFee - expectedProtocolFee; // 50

        // Verify operator contract received fees
        uint256 operatorBalance = token.balanceOf(address(op));
        assertEq(operatorBalance, expectedTotalFee, "Operator should hold total fee");

        // Verify protocol fee tracking
        assertEq(op.accumulatedProtocolFees(address(token)), expectedProtocolFee, "Protocol fee tracking");

        // Distribute fees
        op.distributeFees(address(token));

        // Verify distribution
        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Protocol recipient gets tracked amount");
        assertEq(token.balanceOf(operatorFeeRecipient), expectedOperatorFee, "Operator recipient gets remainder");
        assertEq(op.accumulatedProtocolFees(address(token)), 0, "Tracking reset to 0");
    }

    // ============ Only Protocol Fee (No Operator Calculator) ============

    function test_OnlyProtocolFee_NoOperatorCalculator() public {
        uint256 protocolBps = 100; // 1%

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), protocolBps);
        _authorizePayment(op, paymentInfo);
        op.release(paymentInfo, PAYMENT_AMOUNT);

        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * protocolBps) / 10000; // 100

        // Distribute
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Protocol gets all fees");
        assertEq(token.balanceOf(operatorFeeRecipient), 0, "Operator gets nothing");
    }

    // ============ Only Operator Fee (No Protocol Calculator) ============

    function test_OnlyOperatorFee_NoProtocolCalculator() public {
        uint256 operatorBps = 75; // 0.75%

        // Deploy with no protocol calculator
        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        StaticFeeCalculator opCalc = new StaticFeeCalculator(operatorBps);

        PaymentOperatorFactory factory = new PaymentOperatorFactory(
            address(escrow), address(protocolFeeConfig), owner
        );

        PaymentOperatorFactory.OperatorConfig memory config = _createOperatorConfig(address(opCalc));
        PaymentOperator op = PaymentOperator(factory.deployOperator(config));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), operatorBps);
        _authorizePayment(op, paymentInfo);
        op.release(paymentInfo, PAYMENT_AMOUNT);

        uint256 expectedOperatorFee = (PAYMENT_AMOUNT * operatorBps) / 10000;

        // Distribute
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), 0, "Protocol gets nothing");
        assertEq(token.balanceOf(operatorFeeRecipient), expectedOperatorFee, "Operator gets all fees");
    }

    // ============ Both Calculators Zero (No Fees) ============

    function test_ZeroFees_BothCalculatorsZero() public {
        (PaymentOperator op,) = _deployOperatorWithFees(0, 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 0);
        _authorizePayment(op, paymentInfo);
        op.release(paymentInfo, PAYMENT_AMOUNT);

        // No fees collected
        uint256 operatorBalance = token.balanceOf(address(op));
        assertEq(operatorBalance, 0, "No fees should be collected");

        // distributeFees with 0 balance should be a no-op
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), 0, "Protocol gets nothing");
        assertEq(token.balanceOf(operatorFeeRecipient), 0, "Operator gets nothing");
    }

    // ============ Charge (Direct) with Fees ============

    function test_Charge_WithModularFees() public {
        uint256 protocolBps = 30;
        uint256 operatorBps = 20;
        uint256 totalBps = protocolBps + operatorBps;

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), totalBps);

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        op.charge(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * protocolBps) / 10000;

        // Verify protocol fee tracking from charge
        assertEq(op.accumulatedProtocolFees(address(token)), expectedProtocolFee, "Protocol fee tracked on charge");

        // Distribute
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Protocol gets tracked amount");
    }

    // ============ Multiple Releases Accumulate ============

    function test_MultipleReleases_AccumulateProtocolFees() public {
        uint256 protocolBps = 50;
        uint256 operatorBps = 25;
        uint256 totalBps = protocolBps + operatorBps;

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        // First payment
        AuthCaptureEscrow.PaymentInfo memory paymentInfo1 = _createPaymentInfo(address(op), totalBps);
        paymentInfo1.salt = 1;
        _authorizePayment(op, paymentInfo1);
        op.release(paymentInfo1, PAYMENT_AMOUNT);

        // Second payment
        AuthCaptureEscrow.PaymentInfo memory paymentInfo2 = _createPaymentInfo(address(op), totalBps);
        paymentInfo2.salt = 2;
        _authorizePayment(op, paymentInfo2);
        op.release(paymentInfo2, PAYMENT_AMOUNT);

        uint256 expectedProtocolFee = 2 * ((PAYMENT_AMOUNT * protocolBps) / 10000);
        assertEq(op.accumulatedProtocolFees(address(token)), expectedProtocolFee, "Accumulated over 2 payments");

        // Single distribution
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), expectedProtocolFee, "Protocol gets accumulated total");
        assertEq(op.accumulatedProtocolFees(address(token)), 0, "Reset after distribution");
    }

    // ============ StaticFeeCalculator Tests ============

    function test_StaticFeeCalculator_ReturnsFixedBps() public {
        StaticFeeCalculator calc = new StaticFeeCalculator(42);
        assertEq(calc.FEE_BPS(), 42);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 42);
        assertEq(calc.calculateFee(paymentInfo, 1000, address(this)), 42);
        assertEq(calc.calculateFee(paymentInfo, 0, address(0)), 42);
        assertEq(calc.calculateFee(paymentInfo, type(uint256).max, address(1)), 42);
    }

    function test_StaticFeeCalculator_ZeroBps() public {
        StaticFeeCalculator calc = new StaticFeeCalculator(0);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 0);
        assertEq(calc.calculateFee(paymentInfo, 1000, address(this)), 0);
    }

    // ============ Fee Distribution Edge Cases ============

    function test_DistributeFees_ZeroBalance_NoOp() public {
        (PaymentOperator op,) = _deployOperatorWithFees(50, 25);

        // No fees collected, should be a no-op
        op.distributeFees(address(token));

        assertEq(token.balanceOf(protocolFeeRecipient), 0);
        assertEq(token.balanceOf(operatorFeeRecipient), 0);
    }

    function test_DistributeFees_RevertsOnZeroToken() public {
        (PaymentOperator op,) = _deployOperatorWithFees(50, 25);

        vm.expectRevert();
        op.distributeFees(address(0));
    }

    // ============ Helper Functions ============

    function _deployOperatorWithFees(uint256 protocolBps, uint256 operatorBps)
        internal
        returns (PaymentOperator op, ProtocolFeeConfig protocolFeeConfig)
    {
        // Deploy protocol calculator (or address(0) if 0 bps)
        address protocolCalcAddr = protocolBps > 0 ? address(new StaticFeeCalculator(protocolBps)) : address(0);

        protocolFeeConfig = new ProtocolFeeConfig(protocolCalcAddr, protocolFeeRecipient, owner);

        // Deploy operator calculator (or address(0) if 0 bps)
        address opCalcAddr = operatorBps > 0 ? address(new StaticFeeCalculator(operatorBps)) : address(0);

        PaymentOperatorFactory factory = new PaymentOperatorFactory(
            address(escrow), address(protocolFeeConfig), owner
        );

        PaymentOperatorFactory.OperatorConfig memory config = _createOperatorConfig(opCalcAddr);
        op = PaymentOperator(factory.deployOperator(config));
    }

    function _createOperatorConfig(address feeCalculator)
        internal
        view
        returns (PaymentOperatorFactory.OperatorConfig memory)
    {
        return PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: feeCalculator,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
    }

    function _createPaymentInfo(address op, uint256 totalBps)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: op,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(totalBps),
            maxFeeBps: uint16(totalBps),
            feeReceiver: op,
            salt: 12345
        });
    }

    function _authorizePayment(PaymentOperator op, AuthCaptureEscrow.PaymentInfo memory paymentInfo) internal {
        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, paymentInfo.maxAmount, address(collector), "");
        vm.stopPrank();
    }
}
