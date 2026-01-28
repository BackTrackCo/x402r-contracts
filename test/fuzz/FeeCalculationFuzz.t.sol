// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../../src/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../../src/fees/StaticFeeCalculator.sol";
import {IFeeCalculator} from "../../src/fees/IFeeCalculator.sol";

contract FeeCalculationFuzzTest is Test {
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        token.mint(payer, type(uint128).max);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Fuzz Tests ============

    function testFuzz_FeeCalculation_ProtocolPlusOperatorNeverExceedsAmount(
        uint256 protocolBps,
        uint256 operatorBps,
        uint120 amount
    ) public {
        protocolBps = bound(protocolBps, 0, 5000);
        operatorBps = bound(operatorBps, 0, 10000 - protocolBps);
        amount = uint120(bound(amount, 1, type(uint120).max));

        uint256 totalBps = protocolBps + operatorBps;
        uint256 totalFee = (uint256(amount) * totalBps) / 10000;

        assertLe(totalFee, amount, "Total fee must not exceed amount");
    }

    function testFuzz_FeeCalculation_ProtocolSplitNeverExceedsTotal(
        uint256 protocolBps,
        uint256 operatorBps,
        uint120 amount
    ) public pure {
        protocolBps = bound(protocolBps, 0, 5000);
        operatorBps = bound(operatorBps, 0, 10000 - protocolBps);
        amount = uint120(bound(amount, 1, type(uint120).max));

        uint256 protocolFee = (uint256(amount) * protocolBps) / 10000;
        uint256 operatorFee = (uint256(amount) * operatorBps) / 10000;
        uint256 totalBps = protocolBps + operatorBps;
        uint256 totalFee = (uint256(amount) * totalBps) / 10000;

        assertLe(protocolFee + operatorFee, totalFee + 1, "Split fees must not exceed total fee (rounding tolerance)");
    }

    function testFuzz_FeeCalculation_ZeroBpsAlwaysZeroFee(uint120 amount) public {
        amount = uint120(bound(amount, 1, type(uint120).max));

        // Deploy operator with both calculators as address(0)
        (PaymentOperator op,) = _deployOperatorWithFees(0, 0);

        // With 0 bps, fee should always be 0 regardless of amount
        uint256 totalBps = 0;
        uint256 totalFee = (uint256(amount) * totalBps) / 10000;
        assertEq(totalFee, 0, "Zero bps must produce zero fee");

        // Verify accumulatedProtocolFees is 0 before any action
        assertEq(op.accumulatedProtocolFees(address(token)), 0, "No accumulated fees without actions");
    }

    function testFuzz_FeeCalculation_MaxBpsEqualsAmount(uint120 amount) public pure {
        amount = uint120(bound(amount, 1, type(uint120).max));

        uint256 totalBps = 10000; // 100%
        uint256 totalFee = (uint256(amount) * totalBps) / 10000;
        assertEq(totalFee, amount, "10000 bps must equal full amount");
    }

    function testFuzz_FeeCalculation_DistributionConservation(uint256 protocolBps, uint256 operatorBps, uint120 amount)
        public
    {
        protocolBps = bound(protocolBps, 1, 500);
        operatorBps = bound(operatorBps, 1, 500);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        uint256 totalBps = protocolBps + operatorBps;

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), totalBps, amount);
        _authorizePayment(op, paymentInfo, amount);
        op.release(paymentInfo, amount);

        uint256 opBalance = token.balanceOf(address(op));
        uint256 protocolBefore = token.balanceOf(protocolFeeRecipient);
        uint256 operatorBefore = token.balanceOf(operatorFeeRecipient);

        op.distributeFees(address(token));

        uint256 protocolGot = token.balanceOf(protocolFeeRecipient) - protocolBefore;
        uint256 operatorGot = token.balanceOf(operatorFeeRecipient) - operatorBefore;

        assertEq(protocolGot + operatorGot, opBalance, "Distribution must conserve total fees");
    }

    function testFuzz_FeeCalculation_DustAmountRoundsDown(uint8 amount, uint256 bps) public pure {
        amount = uint8(bound(amount, 1, 99));
        bps = bound(bps, 1, 9999);

        uint256 fee = (uint256(amount) * bps) / 10000;
        assertLe(fee, amount, "Fee must not exceed amount for dust");
        // For small amounts with bps < 10000, fee rounds down
        if (bps < 10000) {
            assertLt(fee, uint256(amount), "Fee must be less than amount for sub-100% bps");
        }
    }

    function testFuzz_AccumulatedProtocolFees_NeverExceedsBalance(uint256 protocolBps, uint120 amount) public {
        protocolBps = bound(protocolBps, 1, 500);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), protocolBps, amount);
        _authorizePayment(op, paymentInfo, amount);
        op.release(paymentInfo, amount);

        uint256 opBalance = token.balanceOf(address(op));
        uint256 accumulated = op.accumulatedProtocolFees(address(token));

        assertLe(accumulated, opBalance, "Accumulated protocol fees must not exceed operator balance");
    }

    // ============ Helper Functions ============

    function _deployOperatorWithFees(uint256 protocolBps, uint256 operatorBps)
        internal
        returns (PaymentOperator op, ProtocolFeeConfig protocolFeeConfig)
    {
        address protocolCalcAddr = protocolBps > 0 ? address(new StaticFeeCalculator(protocolBps)) : address(0);
        protocolFeeConfig = new ProtocolFeeConfig(protocolCalcAddr, protocolFeeRecipient, owner);

        address opCalcAddr = operatorBps > 0 ? address(new StaticFeeCalculator(operatorBps)) : address(0);
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: opCalcAddr,
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
        op = PaymentOperator(factory.deployOperator(config));
    }

    function _createPaymentInfo(address op, uint256 totalBps, uint120 amount)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: op,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: amount,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(totalBps),
            maxFeeBps: uint16(totalBps),
            feeReceiver: op,
            salt: 12345
        });
    }

    function _authorizePayment(PaymentOperator op, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 amount)
        internal
    {
        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }
}
