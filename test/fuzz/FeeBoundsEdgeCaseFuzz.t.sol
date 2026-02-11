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
import {FeeBoundsIncompatible} from "../../src/operator/types/Errors.sol";

/**
 * @title FeeBoundsEdgeCaseFuzzTest
 * @notice Fuzz tests for fee bounds validation edge cases in authorize() and charge()
 * @dev Tests minFeeBps/maxFeeBps boundary conditions, zero-fee operators with non-zero mins,
 *      and the MAX_PROTOCOL_FEE_BPS cap (500 bps).
 */
contract FeeBoundsEdgeCaseFuzzTest is Test {
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

    function testFuzz_AuthorizeRevertsWhenFeeBelowMin(uint256 protocolBps, uint256 operatorBps, uint120 amount) public {
        protocolBps = bound(protocolBps, 0, 400);
        operatorBps = bound(operatorBps, 0, 400);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        uint256 totalBps = protocolBps + operatorBps;
        // minFeeBps strictly above totalBps guarantees revert
        uint16 minFeeBps = uint16(totalBps + 1);
        uint16 maxFeeBps = uint16(minFeeBps + 100);

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(op), minFeeBps, maxFeeBps, amount, 1);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(FeeBoundsIncompatible.selector, uint16(totalBps), minFeeBps, maxFeeBps));
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }

    function testFuzz_AuthorizeRevertsWhenFeeAboveMax(uint256 protocolBps, uint256 operatorBps, uint120 amount) public {
        protocolBps = bound(protocolBps, 1, 500);
        operatorBps = bound(operatorBps, 1, 500);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        uint256 totalBps = protocolBps + operatorBps;
        // maxFeeBps strictly below totalBps guarantees revert
        uint16 maxFeeBps = uint16(totalBps - 1);
        uint16 minFeeBps = 0;

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(op), minFeeBps, maxFeeBps, amount, 2);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(FeeBoundsIncompatible.selector, uint16(totalBps), minFeeBps, maxFeeBps));
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }

    function testFuzz_AuthorizeSucceedsWhenFeeExactlyAtBounds(uint256 protocolBps, uint256 operatorBps, uint120 amount)
        public
    {
        protocolBps = bound(protocolBps, 0, 500);
        operatorBps = bound(operatorBps, 0, 500);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        uint256 totalBps = protocolBps + operatorBps;
        // minFeeBps == maxFeeBps == totalBps: exact match
        uint16 feeBps = uint16(totalBps);

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), feeBps, feeBps, amount, 3);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();

        // Verify authorization succeeded by checking escrow state
        bytes32 hash = escrow.getHash(paymentInfo);
        (, uint256 capturableAmount,) = escrow.paymentState(hash);
        assertEq(capturableAmount, amount, "Payment should be authorized");
    }

    function testFuzz_ChargeRevertsWhenFeeBoundsIncompatible(uint256 protocolBps, uint256 operatorBps, uint120 amount)
        public
    {
        protocolBps = bound(protocolBps, 1, 500);
        operatorBps = bound(operatorBps, 1, 500);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        uint256 totalBps = protocolBps + operatorBps;
        // maxFeeBps below totalBps
        uint16 maxFeeBps = uint16(totalBps - 1);
        uint16 minFeeBps = 0;

        (PaymentOperator op,) = _deployOperatorWithFees(protocolBps, operatorBps);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(op), minFeeBps, maxFeeBps, amount, 4);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(FeeBoundsIncompatible.selector, uint16(totalBps), minFeeBps, maxFeeBps));
        op.charge(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }

    function testFuzz_ZeroFeesWithNonZeroMinReverts(uint120 amount, uint16 minFeeBps) public {
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));
        minFeeBps = uint16(bound(minFeeBps, 1, 10000));

        // Both calculators address(0) -> totalBps = 0
        (PaymentOperator op,) = _deployOperatorWithFees(0, 0);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo =
            _createPaymentInfo(address(op), minFeeBps, minFeeBps, amount, 5);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        vm.expectRevert(abi.encodeWithSelector(FeeBoundsIncompatible.selector, uint16(0), minFeeBps, minFeeBps));
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }

    function testFuzz_MaxProtocolFeeBpsCap(uint256 protocolBps, uint120 amount) public {
        // Protocol calculator > 500 bps, verify capped at 500
        protocolBps = bound(protocolBps, 501, 5000);
        amount = uint120(bound(amount, 10000, 10_000_000 * 10 ** 18));

        // Deploy with high protocol bps — ProtocolFeeConfig caps at MAX_PROTOCOL_FEE_BPS (500)
        address protocolCalcAddr = address(new StaticFeeCalculator(protocolBps));
        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(protocolCalcAddr, protocolFeeRecipient, owner);

        // Verify the cap is applied
        AuthCaptureEscrow.PaymentInfo memory tempInfo = _createPaymentInfo(address(1), 0, 10000, amount, 6);
        uint256 effectiveBps = protocolFeeConfig.getProtocolFeeBps(tempInfo, amount, address(this));
        assertEq(effectiveBps, 500, "Protocol fee must be capped at MAX_PROTOCOL_FEE_BPS (500)");

        // Deploy operator with this config and verify authorize works with capped fee
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: address(0),
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
        PaymentOperator op = PaymentOperator(factory.deployOperator(config));

        // Should succeed with fee bounds matching the capped value (500)
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 500, 500, amount, 7);

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();

        bytes32 hash = escrow.getHash(paymentInfo);
        (, uint256 capturableAmount,) = escrow.paymentState(hash);
        assertEq(capturableAmount, amount, "Payment should be authorized with capped protocol fee");
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

    function _createPaymentInfo(address op, uint16 minFeeBps, uint16 maxFeeBps, uint120 amount, uint256 salt)
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
            minFeeBps: minFeeBps,
            maxFeeBps: maxFeeBps,
            feeReceiver: op,
            salt: salt
        });
    }
}
