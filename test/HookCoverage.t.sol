// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthorizationTimeRecorderHook} from "../src/plugins/hooks/AuthorizationTimeRecorderHook.sol";
import {PaymentIndexRecorderHook} from "../src/plugins/hooks/PaymentIndexRecorderHook.sol";
import {HookCombinator} from "../src/plugins/hooks/combinators/HookCombinator.sol";
import {IHook} from "../src/plugins/hooks/IHook.sol";
import {OnlyOperator} from "../src/types/Errors.sol";

/**
 * @title HookCoverageTest
 * @notice Tests for AuthorizationTimeRecorderHook, PaymentIndexRecorderHook, HookCombinator, BaseHook
 */
contract HookCoverageTest is Test {
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    ProtocolFeeConfig public protocolFeeConfig;
    PaymentOperatorFactory public factory;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        token.mint(payer, PAYMENT_AMOUNT * 100);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ AuthorizationTimeRecorderHook ============

    function test_AuthorizationTimeRecorderHook_RecordsTimestamp() public {
        AuthorizationTimeRecorderHook timeHook = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithHook(address(timeHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 1);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 authTime = timeHook.getAuthorizationTime(paymentInfo);
        assertEq(authTime, block.timestamp, "Auth time should be current timestamp");
    }

    function test_AuthorizationTimeRecorderHook_ReturnsZeroForUnknown() public {
        AuthorizationTimeRecorderHook timeHook = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 99);
        assertEq(timeHook.getAuthorizationTime(paymentInfo), 0, "Should be zero for unknown payment");
    }

    // ============ PaymentIndexRecorderHook ============

    function test_PaymentIndexRecorderHook_IndexesPayerAndReceiver() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithHook(address(indexHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 2);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        assertEq(indexHook.payerPaymentCount(payer), 1, "Payer should have 1 payment");
        assertEq(indexHook.receiverPaymentCount(receiver), 1, "Receiver should have 1 payment");
    }

    function test_PaymentIndexRecorderHook_GetPayerPayments_Pagination() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithHook(address(indexHook));

        // Create 3 payments
        for (uint256 i = 0; i < 3; i++) {
            AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 100 + i);
            vm.prank(payer);
            collector.preApprove(paymentInfo);
            op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        }

        // Get page 1 (offset 0, count 2)
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexHook.getPayerPayments(payer, 0, 2);
        assertEq(total, 3, "Total should be 3");
        assertEq(records.length, 2, "Page should have 2 records");

        // Get page 2 (offset 2, count 2)
        (records, total) = indexHook.getPayerPayments(payer, 2, 2);
        assertEq(records.length, 1, "Last page should have 1 record");
    }

    function test_PaymentIndexRecorderHook_GetPayerPayments_OffsetBeyondTotal() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexHook.getPayerPayments(payer, 100, 10);
        assertEq(total, 0, "Total should be 0 for no payments");
        assertEq(records.length, 0, "Should return empty array");
    }

    function test_PaymentIndexRecorderHook_GetPayerPayments_ZeroCount() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithHook(address(indexHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 3);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexHook.getPayerPayments(payer, 0, 0);
        assertEq(total, 1, "Total should be 1");
        assertEq(records.length, 0, "Should return empty for zero count");
    }

    function test_PaymentIndexRecorderHook_GetPayerPayment_IndexOutOfBounds() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexRecorderHook.IndexOutOfBounds.selector);
        indexHook.getPayerPayment(payer, 0);
    }

    function test_PaymentIndexRecorderHook_GetReceiverPayments() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithHook(address(indexHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 4);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexHook.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 1, "Receiver should have 1 payment");
        assertEq(records.length, 1, "Should return 1 record");
    }

    function test_PaymentIndexRecorderHook_GetReceiverPayment_IndexOutOfBounds() public {
        PaymentIndexRecorderHook indexHook = new PaymentIndexRecorderHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexRecorderHook.IndexOutOfBounds.selector);
        indexHook.getReceiverPayment(receiver, 0);
    }

    // ============ HookCombinator ============

    function test_HookCombinator_E2E_CodehashGate_StateMutation() public {
        // Deploy combinator first so we can read its runtime codehash.
        // Pre-deploy a placeholder hook so the combinator constructor accepts a non-empty array.
        AuthorizationTimeRecorderHook placeholder = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        IHook[] memory placeholderArr = new IHook[](1);
        placeholderArr[0] = IHook(address(placeholder));
        HookCombinator combinator = new HookCombinator(placeholderArr);

        // Real BaseHook subclass gated on the combinator's runtime codehash.
        // EXTCODEHASH (`.codehash`) reads the deployed runtime bytecode hash,
        // which is what BaseHook._verifyAndHash compares against.
        bytes32 combinatorCodehash = address(combinator).codehash;
        PaymentIndexRecorderHook gatedHook = new PaymentIndexRecorderHook(address(escrow), combinatorCodehash);

        // Wire a fresh combinator that actually contains the gated hook.
        IHook[] memory hooks = new IHook[](1);
        hooks[0] = IHook(address(gatedHook));
        HookCombinator realCombinator = new HookCombinator(hooks);
        // Sanity: same bytecode → same codehash → same gate.
        assertEq(address(realCombinator).codehash, combinatorCodehash, "combinator codehash must match");

        PaymentOperator op = _deployWithHook(address(realCombinator));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 7);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // If the codehash gate were broken, BaseHook._verifyAndHash would revert with
        // OnlyOperator (combinator's msg.sender != paymentInfo.operator) and the operator
        // call would have failed. Reaching this assertion proves the gate accepted the
        // combinator and state was mutated.
        assertEq(gatedHook.payerPaymentCount(payer), 1, "Indexed payer payment via combinator");
        assertEq(gatedHook.receiverPaymentCount(receiver), 1, "Indexed receiver payment via combinator");
    }

    function test_HookCombinator_E2E_CodehashMismatch_Reverts() public {
        // Gated on a clearly-wrong codehash; combinator should fail BaseHook auth.
        PaymentIndexRecorderHook gatedHook =
            new PaymentIndexRecorderHook(address(escrow), keccak256("not-the-combinator"));

        IHook[] memory hooks = new IHook[](1);
        hooks[0] = IHook(address(gatedHook));
        HookCombinator combinator = new HookCombinator(hooks);

        PaymentOperator op = _deployWithHook(address(combinator));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 8);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        vm.expectRevert(OnlyOperator.selector);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
    }

    function test_PaymentIndexRecorderHook_ChainSingletonAggregatesAcrossOperators() public {
        // Models the canonical chain-singleton deployment: a single PaymentIndexRecorderHook
        // gated on the HookCombinator runtime codehash, shared by two distinct operators that
        // each route their post-action through their own HookCombinator instance. Because
        // every HookCombinator shares the same runtime bytecode (storage holds the per-instance
        // hook list, not bytecode), the codehash gate accepts both, and the shared singleton's
        // counters aggregate across both operators.

        // Determine the canonical HookCombinator codehash by deploying a placeholder instance.
        AuthorizationTimeRecorderHook placeholder = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        IHook[] memory placeholderArr = new IHook[](1);
        placeholderArr[0] = IHook(address(placeholder));
        bytes32 combinatorCodehash = address(new HookCombinator(placeholderArr)).codehash;

        // One shared singleton, gated on the canonical combinator codehash.
        PaymentIndexRecorderHook sharedHook = new PaymentIndexRecorderHook(address(escrow), combinatorCodehash);
        IHook[] memory hookArr = new IHook[](1);
        hookArr[0] = IHook(address(sharedHook));

        // Two distinct combinator instances — same bytecode, different storage. Codehash is
        // identical on both, so both are accepted by the shared hook's gate.
        HookCombinator combinatorA = new HookCombinator(hookArr);
        HookCombinator combinatorB = new HookCombinator(hookArr);
        assertEq(address(combinatorA).codehash, combinatorCodehash, "combinatorA codehash gate");
        assertEq(address(combinatorB).codehash, combinatorCodehash, "combinatorB codehash gate");

        PaymentOperator opA = _deployWithHook(address(combinatorA));
        PaymentOperator opB = _deployWithHook(address(combinatorB));

        // Fire one authorize through each operator (different salts to avoid hash collision
        // on the same payer/receiver/token).
        AuthCaptureEscrow.PaymentInfo memory infoA = _createPaymentInfo(address(opA), 1001);
        AuthCaptureEscrow.PaymentInfo memory infoB = _createPaymentInfo(address(opB), 1002);

        vm.startPrank(payer);
        collector.preApprove(infoA);
        collector.preApprove(infoB);
        vm.stopPrank();

        opA.authorize(infoA, PAYMENT_AMOUNT, address(collector), "");
        opB.authorize(infoB, PAYMENT_AMOUNT, address(collector), "");

        // Aggregation: one shared singleton sees both authorizations.
        assertEq(sharedHook.payerPaymentCount(payer), 2, "shared singleton aggregates payer count across operators");
        assertEq(
            sharedHook.receiverPaymentCount(receiver), 2, "shared singleton aggregates receiver count across operators"
        );

        // Per-operator filtering: payment hashes are distinct (operator address is part of
        // AuthCaptureEscrow.getHash), so consumers can split the aggregated view by reading
        // PaymentInfo.operator from the indexed structs.
        (AuthCaptureEscrow.PaymentInfo[] memory payments,) = sharedHook.getPayerPayments(payer, 0, 2);
        assertEq(payments.length, 2, "two distinct indexed payments");
        bool sawA = (payments[0].operator == address(opA)) || (payments[1].operator == address(opA));
        bool sawB = (payments[0].operator == address(opB)) || (payments[1].operator == address(opB));
        assertTrue(sawA && sawB, "both operators are reachable via the per-operator filter");
    }

    function test_HookCombinator_GetHookCount() public {
        AuthorizationTimeRecorderHook r1 = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        AuthorizationTimeRecorderHook r2 = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));

        IHook[] memory recs = new IHook[](2);
        recs[0] = IHook(address(r1));
        recs[1] = IHook(address(r2));

        HookCombinator combinator = new HookCombinator(recs);
        assertEq(combinator.getHookCount(), 2, "Should have 2 hooks");
    }

    function test_HookCombinator_GetHooks() public {
        AuthorizationTimeRecorderHook r1 = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));
        AuthorizationTimeRecorderHook r2 = new AuthorizationTimeRecorderHook(address(escrow), bytes32(0));

        IHook[] memory recs = new IHook[](2);
        recs[0] = IHook(address(r1));
        recs[1] = IHook(address(r2));

        HookCombinator combinator = new HookCombinator(recs);
        IHook[] memory retrieved = combinator.getHooks();
        assertEq(retrieved.length, 2, "Should return 2 hooks");
        assertEq(address(retrieved[0]), address(r1), "First hook should match");
        assertEq(address(retrieved[1]), address(r2), "Second hook should match");
    }

    function test_HookCombinator_EmptyHooks_Reverts() public {
        IHook[] memory empty = new IHook[](0);
        vm.expectRevert(HookCombinator.EmptyHooks.selector);
        new HookCombinator(empty);
    }

    function test_HookCombinator_TooManyHooks_Reverts() public {
        IHook[] memory tooMany = new IHook[](11);
        for (uint256 i = 0; i < 11; i++) {
            tooMany[i] = IHook(address(new AuthorizationTimeRecorderHook(address(escrow), bytes32(0))));
        }
        vm.expectRevert();
        new HookCombinator(tooMany);
    }

    function test_HookCombinator_ZeroAddress_Reverts() public {
        IHook[] memory recs = new IHook[](2);
        recs[0] = IHook(address(new AuthorizationTimeRecorderHook(address(escrow), bytes32(0))));
        recs[1] = IHook(address(0));
        vm.expectRevert(abi.encodeWithSelector(HookCombinator.ZeroHook.selector, 1));
        new HookCombinator(recs);
    }

    // ============ BaseHook ============

    function test_BaseHook_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new AuthorizationTimeRecorderHook(address(0), bytes32(0));
    }

    // ============ Helpers ============

    function _deployWithHook(address hook) internal returns (PaymentOperator) {
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: hook,
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
        return PaymentOperator(factory.deployOperator(config));
    }

    function _createPaymentInfo(address op, uint256 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: op,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: op,
            salt: salt
        });
    }
}
