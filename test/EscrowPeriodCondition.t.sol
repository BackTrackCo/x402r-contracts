// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {EscrowPeriod} from "../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezePolicy} from "../src/plugins/escrow-period/freeze-policy/FreezePolicy.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
    EscrowPeriodExpired,
    NotFrozen,
    UnauthorizedFreeze,
    NoFreezePolicy
} from "../src/plugins/escrow-period/types/Errors.sol";

contract EscrowPeriodConditionTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    EscrowPeriod public escrowPeriod;
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
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        PayerCondition payerCondition = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCondition), address(payerCondition), FREEZE_DURATION);
        address escrowPeriodAddr = escrowPeriodFactory.deploy(ESCROW_PERIOD, address(freezePolicy), bytes32(0));
        escrowPeriod = EscrowPeriod(escrowPeriodAddr);

        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
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
        escrowPeriod.freeze(paymentInfo);

        assertTrue(escrowPeriod.isFrozen(paymentInfo));
    }

    // ============ Freeze Edge Cases ============

    function test_FreezeBlocksRelease() public {
        // Deploy with permanent freeze policy (duration=0) so freeze outlasts escrow period
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy permFreezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 0);

        EscrowPeriodFactory condFactory = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = condFactory.deploy(ESCROW_PERIOD, address(permFreezePolicy), bytes32(uint256(200)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        ProtocolFeeConfig pfc2 = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory opFactory2 = new PaymentOperatorFactory(address(escrow), address(pfc2));

        PaymentOperatorFactory.OperatorConfig memory config2 = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(ep2),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(ep2),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator op2 = PaymentOperator(opFactory2.deployOperator(config2));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: address(op2),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(op2),
            salt: 200200
        });

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op2.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Permanently freeze
        vm.prank(payer);
        ep2.freeze(paymentInfo);

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Still frozen (permanent), release should revert
        assertTrue(ep2.isFrozen(paymentInfo));
        vm.prank(receiver);
        vm.expectRevert();
        op2.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_FreezeDuringEscrowPeriod_Succeeds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to midway through escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD / 2);

        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        assertTrue(escrowPeriod.isFrozen(paymentInfo));
    }

    function test_FreezeAfterEscrowPeriod_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD);

        vm.prank(payer);
        vm.expectRevert(EscrowPeriodExpired.selector);
        escrowPeriod.freeze(paymentInfo);
    }

    function test_FreezeAtExactBoundary_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to exact boundary (>=)
        vm.warp(block.timestamp + ESCROW_PERIOD);

        vm.prank(payer);
        vm.expectRevert(EscrowPeriodExpired.selector);
        escrowPeriod.freeze(paymentInfo);
    }

    function test_FreezeOneSecondBeforeBoundary_Succeeds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to one second before boundary
        vm.warp(block.timestamp + ESCROW_PERIOD - 1);

        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        assertTrue(escrowPeriod.isFrozen(paymentInfo));
    }

    // ============ Unfreeze Edge Cases ============

    function test_UnfreezeAllowsRelease() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Freeze
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);
        assertTrue(escrowPeriod.isFrozen(paymentInfo));

        // Unfreeze
        vm.prank(payer);
        escrowPeriod.unfreeze(paymentInfo);
        assertFalse(escrowPeriod.isFrozen(paymentInfo));

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Release should work
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        assertTrue(token.balanceOf(receiver) > 0);
    }

    function test_UnfreezeRevertsIfNotFrozen() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        vm.expectRevert(NotFrozen.selector);
        escrowPeriod.unfreeze(paymentInfo);
    }

    function test_UnfreezeByUnauthorizedCaller_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        // Receiver cannot unfreeze (PayerCondition for unfreeze)
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        escrowPeriod.unfreeze(paymentInfo);
    }

    // ============ Freeze Expiry ============

    function test_FreezeExpiry_AutoUnfreezes() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);
        assertTrue(escrowPeriod.isFrozen(paymentInfo));

        // Warp past freeze duration
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Freeze should have expired
        assertFalse(escrowPeriod.isFrozen(paymentInfo));
    }

    function test_FreezeExpiry_StillBlocksBeforeExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        // Warp to before freeze duration expires but past escrow period
        // This only works if FREEZE_DURATION > ESCROW_PERIOD isn't the case here
        // FREEZE_DURATION = 3 days, ESCROW_PERIOD = 7 days
        // Warp to 2 days (within freeze duration)
        vm.warp(block.timestamp + FREEZE_DURATION - 1);
        assertTrue(escrowPeriod.isFrozen(paymentInfo), "Should still be frozen before expiry");
    }

    // ============ Multiple Cycles ============

    function test_MultipleFreezeUnfreezeCycles() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Cycle 1: freeze then unfreeze
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);
        assertTrue(escrowPeriod.isFrozen(paymentInfo));

        vm.prank(payer);
        escrowPeriod.unfreeze(paymentInfo);
        assertFalse(escrowPeriod.isFrozen(paymentInfo));

        // Cycle 2: freeze again (still within escrow period)
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);
        assertTrue(escrowPeriod.isFrozen(paymentInfo));

        vm.prank(payer);
        escrowPeriod.unfreeze(paymentInfo);
        assertFalse(escrowPeriod.isFrozen(paymentInfo));
    }

    function test_RefreezeAfterExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // First freeze
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        // Wait for freeze to expire
        vm.warp(block.timestamp + FREEZE_DURATION + 1);
        assertFalse(escrowPeriod.isFrozen(paymentInfo));

        // Refreeze (still within escrow period: ESCROW_PERIOD=7d > FREEZE_DURATION=3d)
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);
        assertTrue(escrowPeriod.isFrozen(paymentInfo));
    }

    // ============ Authorization & View Functions ============

    function test_ReceiverCannotFreeze() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        escrowPeriod.freeze(paymentInfo);
    }

    function test_ReleaseWhileFrozen_Reverts() public {
        // Deploy a permanent freeze policy (duration=0 means permanent)
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy permFreezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 0);

        EscrowPeriodFactory condFactory = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = condFactory.deploy(ESCROW_PERIOD, address(permFreezePolicy), bytes32(uint256(99)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        ProtocolFeeConfig pfc2 = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory opFactory2 = new PaymentOperatorFactory(address(escrow), address(pfc2));

        PaymentOperatorFactory.OperatorConfig memory config2 = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(ep2),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(ep2),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        PaymentOperator op2 = PaymentOperator(opFactory2.deployOperator(config2));

        AuthCaptureEscrow.PaymentInfo memory pi = AuthCaptureEscrow.PaymentInfo({
            operator: address(op2),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(op2),
            salt: 99999
        });

        vm.prank(payer);
        collector.preApprove(pi);
        op2.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        // Permanent freeze
        vm.prank(payer);
        ep2.freeze(pi);
        assertTrue(ep2.isFrozen(pi));

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Still frozen (permanent)
        assertTrue(ep2.isFrozen(pi));

        // Release should revert
        vm.prank(receiver);
        vm.expectRevert();
        op2.release(pi, PAYMENT_AMOUNT);
    }

    function test_NoFreezePolicyDeployed_FreezeReverts() public {
        // Deploy without freeze policy
        EscrowPeriodFactory epFactory2 = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = epFactory2.deploy(ESCROW_PERIOD, address(0), bytes32(uint256(1)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        vm.expectRevert(NoFreezePolicy.selector);
        ep2.freeze(paymentInfo);
    }

    function test_CanReleaseAfterFreezeExpiresAndEscrowPeriodPasses() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Freeze
        vm.prank(payer);
        escrowPeriod.freeze(paymentInfo);

        // Warp past both freeze duration AND escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Freeze duration (3 days) < escrow period (7 days), so freeze is already expired
        assertFalse(escrowPeriod.isFrozen(paymentInfo));

        // Release should succeed
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        assertTrue(token.balanceOf(receiver) > 0);
    }

    function test_IsEscrowPeriodPassed_BeforeAndAfter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Before: not passed
        (bool passedBefore,) = escrowPeriod.isEscrowPeriodPassed(paymentInfo);
        assertFalse(passedBefore, "Escrow period should not be passed initially");

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD);

        // After: passed
        (bool passedAfter,) = escrowPeriod.isEscrowPeriodPassed(paymentInfo);
        assertTrue(passedAfter, "Escrow period should be passed after warp");
    }

    function test_CanRelease_AllConditions() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Initially: cannot release (escrow period not passed)
        assertFalse(escrowPeriod.canRelease(paymentInfo));

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Now can release
        assertTrue(escrowPeriod.canRelease(paymentInfo));
    }

    // ============ Internal Helpers ============

    function _authorizePayment() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        return paymentInfo;
    }
}
