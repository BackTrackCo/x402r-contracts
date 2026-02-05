// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {EscrowPeriod} from "../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {Freeze} from "../src/plugins/freeze/Freeze.sol";
import {ICondition} from "../src/plugins/conditions/ICondition.sol";
import {AndCondition} from "../src/plugins/conditions/combinators/AndCondition.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FreezeWindowExpired, NotFrozen, UnauthorizedFreeze} from "../src/plugins/freeze/types/Errors.sol";

contract FreezeConditionTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    EscrowPeriod public escrowPeriod;
    Freeze public freeze;
    AndCondition public releaseCondition;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant ESCROW_PERIOD_DURATION = 7 days;
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

        // Deploy escrow period via factory
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        address escrowPeriodAddr = escrowPeriodFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(0));
        escrowPeriod = EscrowPeriod(escrowPeriodAddr);

        // Deploy freeze with escrow period constraint
        PayerCondition payerCondition = new PayerCondition();
        freeze = new Freeze(
            address(payerCondition), address(payerCondition), FREEZE_DURATION, address(escrowPeriod), address(escrow)
        );

        // Compose both conditions with AndCondition
        ICondition[] memory conditions = new ICondition[](2);
        conditions[0] = ICondition(address(escrowPeriod));
        conditions[1] = ICondition(address(freeze));
        releaseCondition = new AndCondition(conditions);

        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
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

    function _authorizePayment() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        return paymentInfo;
    }

    // ============ Basic Freeze ============

    function test_PayerCanFreezePayment() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        assertTrue(freeze.isFrozen(paymentInfo));
    }

    function test_FreezeBlocksRelease() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Deploy with permanent freeze (duration=0)
        PayerCondition payerCond = new PayerCondition();

        // Deploy a separate escrow period + freeze + operator for this test
        EscrowPeriodFactory condFactory = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = condFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(uint256(200)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        Freeze freeze2 = new Freeze(address(payerCond), address(payerCond), 0, address(ep2), address(escrow));

        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(ep2));
        conds[1] = ICondition(address(freeze2));
        AndCondition relCond = new AndCondition(conds);

        ProtocolFeeConfig pfc2 = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory opFactory2 = new PaymentOperatorFactory(address(escrow), address(pfc2));

        PaymentOperatorFactory.OperatorConfig memory config2 = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(ep2),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(relCond),
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
            salt: 200200
        });

        vm.prank(payer);
        collector.preApprove(pi);
        op2.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        // Permanently freeze
        vm.prank(payer);
        freeze2.freeze(pi);

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Still frozen (permanent), release should revert
        assertTrue(freeze2.isFrozen(pi));
        vm.prank(receiver);
        vm.expectRevert();
        op2.release(pi, PAYMENT_AMOUNT);
    }

    // ============ Freeze Edge Cases ============

    function test_FreezeDuringEscrowPeriod_Succeeds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to midway through escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION / 2);

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        assertTrue(freeze.isFrozen(paymentInfo));
    }

    function test_FreezeAfterEscrowPeriod_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION);

        vm.prank(payer);
        vm.expectRevert(FreezeWindowExpired.selector);
        freeze.freeze(paymentInfo);
    }

    function test_FreezeAtExactBoundary_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to exact boundary (>=)
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION);

        vm.prank(payer);
        vm.expectRevert(FreezeWindowExpired.selector);
        freeze.freeze(paymentInfo);
    }

    function test_FreezeOneSecondBeforeBoundary_Succeeds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Warp to one second before boundary
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION - 1);

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        assertTrue(freeze.isFrozen(paymentInfo));
    }

    // ============ Unfreeze Edge Cases ============

    function test_UnfreezeAllowsRelease() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Freeze
        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo));

        // Unfreeze
        vm.prank(payer);
        freeze.unfreeze(paymentInfo);
        assertFalse(freeze.isFrozen(paymentInfo));

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Release should work
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        assertTrue(token.balanceOf(receiver) > 0);
    }

    function test_UnfreezeRevertsIfNotFrozen() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        vm.expectRevert(NotFrozen.selector);
        freeze.unfreeze(paymentInfo);
    }

    function test_UnfreezeByUnauthorizedCaller_Reverts() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        // Receiver cannot unfreeze (PayerCondition for unfreeze)
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        freeze.unfreeze(paymentInfo);
    }

    // ============ Freeze Expiry ============

    function test_FreezeExpiry_AutoUnfreezes() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo));

        // Warp past freeze duration
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Freeze should have expired
        assertFalse(freeze.isFrozen(paymentInfo));
    }

    function test_FreezeExpiry_StillBlocksBeforeExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        // Warp to before freeze duration expires
        vm.warp(block.timestamp + FREEZE_DURATION - 1);
        assertTrue(freeze.isFrozen(paymentInfo), "Should still be frozen before expiry");
    }

    // ============ Multiple Cycles ============

    function test_MultipleFreezeUnfreezeCycles() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Cycle 1: freeze then unfreeze
        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo));

        vm.prank(payer);
        freeze.unfreeze(paymentInfo);
        assertFalse(freeze.isFrozen(paymentInfo));

        // Cycle 2: freeze again (still within escrow period)
        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo));

        vm.prank(payer);
        freeze.unfreeze(paymentInfo);
        assertFalse(freeze.isFrozen(paymentInfo));
    }

    function test_RefreezeAfterExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // First freeze
        vm.prank(payer);
        freeze.freeze(paymentInfo);

        // Wait for freeze to expire
        vm.warp(block.timestamp + FREEZE_DURATION + 1);
        assertFalse(freeze.isFrozen(paymentInfo));

        // Refreeze (still within escrow period: ESCROW_PERIOD=7d > FREEZE_DURATION=3d)
        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo));
    }

    // ============ Authorization & View Functions ============

    function test_ReceiverCannotFreeze() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        freeze.freeze(paymentInfo);
    }

    function test_ReleaseWhileFrozen_Reverts() public {
        // Deploy a permanent freeze (duration=0 means permanent)
        PayerCondition payerCond = new PayerCondition();

        EscrowPeriodFactory condFactory = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = condFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(uint256(99)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        Freeze freeze2 = new Freeze(address(payerCond), address(payerCond), 0, address(ep2), address(escrow));

        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(ep2));
        conds[1] = ICondition(address(freeze2));
        AndCondition relCond = new AndCondition(conds);

        ProtocolFeeConfig pfc2 = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory opFactory2 = new PaymentOperatorFactory(address(escrow), address(pfc2));

        PaymentOperatorFactory.OperatorConfig memory config2 = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(ep2),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(relCond),
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
        freeze2.freeze(pi);
        assertTrue(freeze2.isFrozen(pi));

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Still frozen (permanent)
        assertTrue(freeze2.isFrozen(pi));

        // Release should revert
        vm.prank(receiver);
        vm.expectRevert();
        op2.release(pi, PAYMENT_AMOUNT);
    }

    function test_CanReleaseAfterFreezeExpiresAndEscrowPeriodPasses() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Freeze
        vm.prank(payer);
        freeze.freeze(paymentInfo);

        // Warp past both freeze duration AND escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Freeze duration (3 days) < escrow period (7 days), so freeze is already expired
        assertFalse(freeze.isFrozen(paymentInfo));

        // Release should succeed
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        assertTrue(token.balanceOf(receiver) > 0);
    }

    // ============ Freeze Without Escrow Period Constraint ============

    function test_FreezeWithoutEscrowPeriod_UnconstrainedByTime() public {
        // Deploy freeze without escrow period constraint
        PayerCondition payerCond = new PayerCondition();
        Freeze unconstrainedFreeze =
            new Freeze(address(payerCond), address(payerCond), FREEZE_DURATION, address(0), address(escrow));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        // Can freeze even after escrow period passes
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        vm.prank(payer);
        unconstrainedFreeze.freeze(paymentInfo);
        assertTrue(unconstrainedFreeze.isFrozen(paymentInfo));
    }

    // ============ Check Function ============

    function test_Check_ReturnsTrueWhenNotFrozen() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        assertTrue(freeze.check(paymentInfo, 0, address(0)), "Should return true when not frozen");
    }

    function test_Check_ReturnsFalseWhenFrozen() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment();

        vm.prank(payer);
        freeze.freeze(paymentInfo);

        assertFalse(freeze.check(paymentInfo, 0, address(0)), "Should return false when frozen");
    }
}
