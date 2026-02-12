// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {EscrowPeriod} from "../../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {Freeze} from "../../src/plugins/freeze/Freeze.sol";
import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {AndCondition} from "../../src/plugins/conditions/combinators/AndCondition.sol";
import {PayerCondition} from "../../src/plugins/conditions/access/PayerCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FreezeWindowExpired} from "../../src/plugins/freeze/types/Errors.sol";

/**
 * @title FreezeEscrowBoundaryFuzzTest
 * @notice Fuzz tests for freeze/escrow period boundary conditions and race conditions
 * @dev Tests the documented race condition where freeze() reverts at the exact moment
 *      EscrowPeriod.check() returns true (release allowed).
 */
contract FreezeEscrowBoundaryFuzzTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    EscrowPeriod public escrowPeriod;
    Freeze public freeze;
    Freeze public permanentFreeze;
    AndCondition public releaseCondition;
    MockERC20 public token;
    PayerCondition public payerCondition;

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
        payerCondition = new PayerCondition();
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

    // ============ Fuzz Tests ============

    function testFuzz_FreezeAtBoundary(uint256 warpOffset) public {
        // Freeze succeeds before ESCROW_PERIOD, reverts at/after
        warpOffset = bound(warpOffset, 0, ESCROW_PERIOD_DURATION * 2);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment(1);
        uint256 authTime = block.timestamp;

        vm.warp(authTime + warpOffset);

        if (warpOffset < ESCROW_PERIOD_DURATION) {
            // Before boundary: freeze should succeed
            vm.prank(payer);
            freeze.freeze(paymentInfo);
            assertTrue(freeze.isFrozen(paymentInfo), "Should be frozen before escrow period ends");
        } else {
            // At or after boundary: freeze should revert
            vm.prank(payer);
            vm.expectRevert(FreezeWindowExpired.selector);
            freeze.freeze(paymentInfo);
        }
    }

    function testFuzz_ReleaseWithFreezeAndEscrowPeriod(uint256 freezeOffset, uint256 releaseOffset) public {
        // Release succeeds only when both escrow period passed AND freeze expired
        freezeOffset = bound(freezeOffset, 0, ESCROW_PERIOD_DURATION - 1);
        releaseOffset = bound(releaseOffset, 0, ESCROW_PERIOD_DURATION * 3);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment(2);
        uint256 authTime = block.timestamp;

        // Freeze during escrow period
        vm.warp(authTime + freezeOffset);
        vm.prank(payer);
        freeze.freeze(paymentInfo);

        // Attempt release at releaseOffset after auth
        vm.warp(authTime + releaseOffset);

        // Query on-chain state to determine expected behavior
        bool escrowPeriodAllows = !escrowPeriod.isDuringEscrowPeriod(paymentInfo);
        bool freezeAllows = !freeze.isFrozen(paymentInfo);

        if (escrowPeriodAllows && freezeAllows) {
            // Both conditions met: release should succeed
            vm.prank(receiver);
            operator.release(paymentInfo, PAYMENT_AMOUNT);
            assertTrue(token.balanceOf(receiver) > 0, "Receiver should have tokens after release");
        } else {
            // At least one condition not met: release should revert
            vm.prank(receiver);
            vm.expectRevert();
            operator.release(paymentInfo, PAYMENT_AMOUNT);
        }
    }

    function testFuzz_FreezeReleaseRaceAtExactBoundary() public {
        // Verifies the documented race condition:
        // 1 second before boundary: freeze works, release blocked
        // At boundary: freeze reverts, release becomes possible
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizePayment(3);
        uint256 authTime = block.timestamp;

        // 1 second before boundary: freeze should work
        vm.warp(authTime + ESCROW_PERIOD_DURATION - 1);

        vm.prank(payer);
        freeze.freeze(paymentInfo);
        assertTrue(freeze.isFrozen(paymentInfo), "Should be frozen 1 second before boundary");

        // Release should fail (still in escrow period AND frozen)
        vm.prank(receiver);
        vm.expectRevert();
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // Unfreeze so we can test the boundary release
        vm.prank(payer);
        freeze.unfreeze(paymentInfo);

        // At the exact boundary: freeze should revert
        vm.warp(authTime + ESCROW_PERIOD_DURATION);

        vm.prank(payer);
        vm.expectRevert(FreezeWindowExpired.selector);
        freeze.freeze(paymentInfo);

        // Release should succeed (escrow period passed, not frozen)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
        assertTrue(token.balanceOf(receiver) > 0, "Receiver should have tokens at boundary");
    }

    function testFuzz_PermanentFreezeBlocksReleaseIndefinitely(uint256 releaseTimeDelta) public {
        releaseTimeDelta = bound(releaseTimeDelta, ESCROW_PERIOD_DURATION + 1, 365 days);

        // Deploy permanent freeze (duration=0) with separate operator
        Freeze permFreeze =
            new Freeze(address(payerCondition), address(payerCondition), 0, address(escrowPeriod), address(escrow));

        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(escrowPeriod));
        conds[1] = ICondition(address(permFreeze));
        AndCondition relCond = new AndCondition(conds);

        // Deploy separate escrow period for independent recording
        EscrowPeriodFactory epFactory = new EscrowPeriodFactory(address(escrow));
        address ep2Addr = epFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(uint256(42)));
        EscrowPeriod ep2 = EscrowPeriod(ep2Addr);

        // Redeploy freeze with this new escrow period
        Freeze permFreeze2 =
            new Freeze(address(payerCondition), address(payerCondition), 0, address(ep2), address(escrow));

        ICondition[] memory conds2 = new ICondition[](2);
        conds2[0] = ICondition(address(ep2));
        conds2[1] = ICondition(address(permFreeze2));
        AndCondition relCond2 = new AndCondition(conds2);

        ProtocolFeeConfig pfc2 = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        PaymentOperatorFactory opFactory2 = new PaymentOperatorFactory(address(escrow), address(pfc2));

        PaymentOperatorFactory.OperatorConfig memory config2 = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(ep2),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(relCond2),
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
            salt: 424242
        });

        vm.prank(payer);
        collector.preApprove(pi);
        op2.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        // Permanently freeze
        vm.prank(payer);
        permFreeze2.freeze(pi);
        assertTrue(permFreeze2.isFrozen(pi), "Should be permanently frozen");

        // Warp far into the future
        vm.warp(block.timestamp + releaseTimeDelta);

        // Should still be frozen (permanent = type(uint256).max)
        assertTrue(permFreeze2.isFrozen(pi), "Permanent freeze should persist");

        // Release should always revert
        vm.prank(receiver);
        vm.expectRevert();
        op2.release(pi, PAYMENT_AMOUNT);
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
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: salt
        });
    }

    function _authorizePayment(uint256 salt) internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(salt);

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        return paymentInfo;
    }
}
