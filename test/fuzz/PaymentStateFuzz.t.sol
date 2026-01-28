// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {PaymentState} from "../../src/operator/types/Types.sol";

contract PaymentStateFuzzTest is Test {
    PaymentOperator public operator;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
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
        operator = PaymentOperator(factory.deployOperator(config));

        token.mint(payer, type(uint128).max);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Fuzz Tests ============

    function testFuzz_PaymentState_AuthorizeToInEscrow(uint120 amount, uint256 salt) public {
        amount = uint120(bound(amount, 1, 10_000_000 * 10 ** 18));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);
        _authorizePayment(paymentInfo, amount);

        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.InEscrow), "Must be InEscrow after authorize");
    }

    function testFuzz_PaymentState_ReleaseToReleased(uint120 amount, uint256 salt) public {
        amount = uint120(bound(amount, 1, 10_000_000 * 10 ** 18));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);
        _authorizePayment(paymentInfo, amount);

        operator.release(paymentInfo, amount);

        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.Released), "Must be Released after full release");
    }

    function testFuzz_PaymentState_RefundReducesCapturable(uint120 amount, uint120 refundAmount, uint256 salt) public {
        amount = uint120(bound(amount, 2, 10_000_000 * 10 ** 18));
        refundAmount = uint120(bound(refundAmount, 1, amount - 1)); // partial refund

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);
        _authorizePayment(paymentInfo, amount);

        bytes32 hash = escrow.getHash(paymentInfo);
        (, uint120 capturableBefore,) = escrow.paymentState(hash);

        operator.refundInEscrow(paymentInfo, refundAmount);

        (, uint120 capturableAfter,) = escrow.paymentState(hash);
        assertEq(capturableAfter, capturableBefore - refundAmount, "Capturable must decrease by refund amount");

        // State should still be InEscrow (partial refund)
        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.InEscrow), "Must still be InEscrow after partial refund");
    }

    function testFuzz_PaymentState_ExpiredAfterAuthExpiry(uint120 amount, uint256 salt, uint48 warpDelta) public {
        amount = uint120(bound(amount, 1, 10_000_000 * 10 ** 18));
        warpDelta = uint48(bound(warpDelta, 7 days + 1, 365 days));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);
        _authorizePayment(paymentInfo, amount);

        // Warp past authorizationExpiry
        vm.warp(block.timestamp + warpDelta);

        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.Expired), "Must be Expired after authorizationExpiry");
    }

    function testFuzz_PaymentState_NonExistentForUnauthorized(uint120 amount, uint256 salt) public {
        amount = uint120(bound(amount, 1, type(uint120).max));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);

        // Without authorizing, state should be NonExistent
        PaymentState state = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state), uint256(PaymentState.NonExistent), "Must be NonExistent without authorization");
    }

    function testFuzz_PaymentState_MonotonicTransitions(uint120 amount, uint120 releaseAmount, uint256 salt) public {
        amount = uint120(bound(amount, 2, 10_000_000 * 10 ** 18));
        releaseAmount = uint120(bound(releaseAmount, 1, amount));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);

        // NonExistent
        PaymentState state0 = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state0), uint256(PaymentState.NonExistent), "Start: NonExistent");

        // Authorize -> InEscrow
        _authorizePayment(paymentInfo, amount);
        PaymentState state1 = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state1), uint256(PaymentState.InEscrow), "After authorize: InEscrow");

        // InEscrow -> Released (full release)
        operator.release(paymentInfo, amount);
        PaymentState state2 = operator.getPaymentState(paymentInfo);
        assertEq(uint256(state2), uint256(PaymentState.Released), "After release: Released");

        // State moves forward: NonExistent(0) -> InEscrow(1) -> Released(2)
        assertTrue(uint256(state0) < uint256(state1), "State must advance: NonExistent < InEscrow");
        assertTrue(uint256(state1) < uint256(state2), "State must advance: InEscrow < Released");
    }

    // ============ Helper Functions ============

    function _createPaymentInfo(uint120 amount, uint256 salt)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: amount,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: salt
        });
    }

    function _authorizePayment(AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 amount) internal {
        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }
}
