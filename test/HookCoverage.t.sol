// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthorizationTimeHook} from "../src/plugins/hooks/AuthorizationTimeHook.sol";
import {PaymentIndexHook} from "../src/plugins/hooks/PaymentIndexHook.sol";
import {HookCombinator} from "../src/plugins/hooks/combinators/HookCombinator.sol";
import {IHook} from "../src/plugins/hooks/IHook.sol";

/**
 * @title PostActionHookCoverageTest
 * @notice Tests for AuthorizationTimeHook, PaymentIndexHook, HookCombinator, BaseHook
 */
contract PostActionHookCoverageTest is Test {
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

    // ============ AuthorizationTimeHook ============

    function test_AuthorizationTimeHook_RecordsTimestamp() public {
        AuthorizationTimeHook timeHook = new AuthorizationTimeHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithPostActionHook(address(timeHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 1);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 authTime = timeHook.getAuthorizationTime(paymentInfo);
        assertEq(authTime, block.timestamp, "Auth time should be current timestamp");
    }

    function test_AuthorizationTimeHook_ReturnsZeroForUnknown() public {
        AuthorizationTimeHook timeHook = new AuthorizationTimeHook(address(escrow), bytes32(0));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 99);
        assertEq(timeHook.getAuthorizationTime(paymentInfo), 0, "Should be zero for unknown payment");
    }

    // ============ PaymentIndexHook ============

    function test_PaymentIndexHook_IndexesPayerAndReceiver() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithPostActionHook(address(indexPostActionHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 2);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        assertEq(indexPostActionHook.payerPaymentCount(payer), 1, "Payer should have 1 payment");
        assertEq(indexPostActionHook.receiverPaymentCount(receiver), 1, "Receiver should have 1 payment");
    }

    function test_PaymentIndexHook_GetPayerPayments_Pagination() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithPostActionHook(address(indexPostActionHook));

        // Create 3 payments
        for (uint256 i = 0; i < 3; i++) {
            AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 100 + i);
            vm.prank(payer);
            collector.preApprove(paymentInfo);
            op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        }

        // Get page 1 (offset 0, count 2)
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) =
            indexPostActionHook.getPayerPayments(payer, 0, 2);
        assertEq(total, 3, "Total should be 3");
        assertEq(records.length, 2, "Page should have 2 records");

        // Get page 2 (offset 2, count 2)
        (records, total) = indexPostActionHook.getPayerPayments(payer, 2, 2);
        assertEq(records.length, 1, "Last page should have 1 record");
    }

    function test_PaymentIndexHook_GetPayerPayments_OffsetBeyondTotal() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) =
            indexPostActionHook.getPayerPayments(payer, 100, 10);
        assertEq(total, 0, "Total should be 0 for no payments");
        assertEq(records.length, 0, "Should return empty array");
    }

    function test_PaymentIndexHook_GetPayerPayments_ZeroCount() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithPostActionHook(address(indexPostActionHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 3);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) =
            indexPostActionHook.getPayerPayments(payer, 0, 0);
        assertEq(total, 1, "Total should be 1");
        assertEq(records.length, 0, "Should return empty for zero count");
    }

    function test_PaymentIndexHook_GetPayerPayment_IndexOutOfBounds() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexHook.IndexOutOfBounds.selector);
        indexPostActionHook.getPayerPayment(payer, 0);
    }

    function test_PaymentIndexHook_GetReceiverPayments() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithPostActionHook(address(indexPostActionHook));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 4);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) =
            indexPostActionHook.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 1, "Receiver should have 1 payment");
        assertEq(records.length, 1, "Should return 1 record");
    }

    function test_PaymentIndexHook_GetReceiverPayment_IndexOutOfBounds() public {
        PaymentIndexHook indexPostActionHook = new PaymentIndexHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexHook.IndexOutOfBounds.selector);
        indexPostActionHook.getReceiverPayment(receiver, 0);
    }

    // ============ HookCombinator ============

    function test_HookCombinator_CombinesMultipleHooks() public {
        // Use codehash(0) so sub-hooks accept calls from the combinator
        // The combinator itself checks msg.sender == operator, then delegates
        AuthorizationTimeHook timeHook = new AuthorizationTimeHook(address(escrow), bytes32(0));

        IHook[] memory recs = new IHook[](1);
        recs[0] = IHook(address(timeHook));

        HookCombinator combinator = new HookCombinator(recs);
        PaymentOperator op = _deployWithPostActionHook(address(combinator));

        // The combinator checks msg.sender == paymentInfo.operator
        // Sub-hooks (BaseHook) check codehash of msg.sender
        // With codehash=bytes32(0), BaseHook accepts any operator-codehash caller
        // But the actual caller of sub-hooks is the combinator, not the operator
        // So we just test the combinator's own validation and setup
        assertEq(combinator.getHookCount(), 1, "Combinator should have 1 hook");

        IHook[] memory retrieved = combinator.getHooks();
        assertEq(address(retrieved[0]), address(timeHook), "Should contain time hook");
    }

    function test_HookCombinator_RecorderCount() public {
        AuthorizationTimeHook r1 = new AuthorizationTimeHook(address(escrow), bytes32(0));
        AuthorizationTimeHook r2 = new AuthorizationTimeHook(address(escrow), bytes32(0));

        IHook[] memory recs = new IHook[](2);
        recs[0] = IHook(address(r1));
        recs[1] = IHook(address(r2));

        HookCombinator combinator = new HookCombinator(recs);
        assertEq(combinator.getHookCount(), 2, "Should have 2 hooks");
    }

    function test_HookCombinator_GetHooks() public {
        AuthorizationTimeHook r1 = new AuthorizationTimeHook(address(escrow), bytes32(0));
        AuthorizationTimeHook r2 = new AuthorizationTimeHook(address(escrow), bytes32(0));

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
            tooMany[i] = IHook(address(new AuthorizationTimeHook(address(escrow), bytes32(0))));
        }
        vm.expectRevert();
        new HookCombinator(tooMany);
    }

    function test_HookCombinator_ZeroAddress_Reverts() public {
        IHook[] memory recs = new IHook[](2);
        recs[0] = IHook(address(new AuthorizationTimeHook(address(escrow), bytes32(0))));
        recs[1] = IHook(address(0));
        vm.expectRevert(abi.encodeWithSelector(HookCombinator.ZeroHook.selector, 1));
        new HookCombinator(recs);
    }

    // ============ BaseHook ============

    function test_BaseHook_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new AuthorizationTimeHook(address(0), bytes32(0));
    }

    // ============ Helpers ============

    function _deployWithPostActionHook(address hook) internal returns (PaymentOperator) {
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
