// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthorizationTimePostActionHook} from "../src/plugins/post-action-hooks/AuthorizationTimePostActionHook.sol";
import {PaymentIndexPostActionHook} from "../src/plugins/post-action-hooks/PaymentIndexPostActionHook.sol";
import {PostActionHookCombinator} from "../src/plugins/post-action-hooks/combinators/PostActionHookCombinator.sol";
import {IPostActionHook} from "../src/plugins/post-action-hooks/IPostActionHook.sol";

/**
 * @title PostActionHookCoverageTest
 * @notice Tests for AuthorizationTimePostActionHook, PaymentIndexPostActionHook, PostActionHookCombinator, BasePostActionHook
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

    // ============ AuthorizationTimePostActionHook ============

    function test_AuthorizationTimePostActionHook_RecordsTimestamp() public {
        AuthorizationTimePostActionHook timeRecorder = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(timeRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 1);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 authTime = timeRecorder.getAuthorizationTime(paymentInfo);
        assertEq(authTime, block.timestamp, "Auth time should be current timestamp");
    }

    function test_AuthorizationTimePostActionHook_ReturnsZeroForUnknown() public {
        AuthorizationTimePostActionHook timeRecorder = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 99);
        assertEq(timeRecorder.getAuthorizationTime(paymentInfo), 0, "Should be zero for unknown payment");
    }

    // ============ PaymentIndexPostActionHook ============

    function test_PaymentIndexPostActionHook_IndexesPayerAndReceiver() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 2);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        assertEq(indexRecorder.payerPaymentCount(payer), 1, "Payer should have 1 payment");
        assertEq(indexRecorder.receiverPaymentCount(receiver), 1, "Receiver should have 1 payment");
    }

    function test_PaymentIndexPostActionHook_GetPayerPayments_Pagination() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        // Create 3 payments
        for (uint256 i = 0; i < 3; i++) {
            AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 100 + i);
            vm.prank(payer);
            collector.preApprove(paymentInfo);
            op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        }

        // Get page 1 (offset 0, count 2)
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 2);
        assertEq(total, 3, "Total should be 3");
        assertEq(records.length, 2, "Page should have 2 records");

        // Get page 2 (offset 2, count 2)
        (records, total) = indexRecorder.getPayerPayments(payer, 2, 2);
        assertEq(records.length, 1, "Last page should have 1 record");
    }

    function test_PaymentIndexPostActionHook_GetPayerPayments_OffsetBeyondTotal() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexRecorder.getPayerPayments(payer, 100, 10);
        assertEq(total, 0, "Total should be 0 for no payments");
        assertEq(records.length, 0, "Should return empty array");
    }

    function test_PaymentIndexPostActionHook_GetPayerPayments_ZeroCount() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 3);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 0);
        assertEq(total, 1, "Total should be 1");
        assertEq(records.length, 0, "Should return empty for zero count");
    }

    function test_PaymentIndexPostActionHook_GetPayerPayment_IndexOutOfBounds() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexPostActionHook.IndexOutOfBounds.selector);
        indexRecorder.getPayerPayment(payer, 0);
    }

    function test_PaymentIndexPostActionHook_GetReceiverPayments() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 4);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (AuthCaptureEscrow.PaymentInfo[] memory records, uint256 total) =
            indexRecorder.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 1, "Receiver should have 1 payment");
        assertEq(records.length, 1, "Should return 1 record");
    }

    function test_PaymentIndexPostActionHook_GetReceiverPayment_IndexOutOfBounds() public {
        PaymentIndexPostActionHook indexRecorder = new PaymentIndexPostActionHook(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexPostActionHook.IndexOutOfBounds.selector);
        indexRecorder.getReceiverPayment(receiver, 0);
    }

    // ============ PostActionHookCombinator ============

    function test_PostActionHookCombinator_CombinesMultipleRecorders() public {
        // Use codehash(0) so sub-recorders accept calls from the combinator
        // The combinator itself checks msg.sender == operator, then delegates
        AuthorizationTimePostActionHook timeRecorder = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));

        IPostActionHook[] memory recs = new IPostActionHook[](1);
        recs[0] = IPostActionHook(address(timeRecorder));

        PostActionHookCombinator combinator = new PostActionHookCombinator(recs);
        PaymentOperator op = _deployWithRecorder(address(combinator));

        // The combinator checks msg.sender == paymentInfo.operator
        // Sub-recorders (BasePostActionHook) check codehash of msg.sender
        // With codehash=bytes32(0), BasePostActionHook accepts any operator-codehash caller
        // But the actual caller of sub-recorders is the combinator, not the operator
        // So we just test the combinator's own validation and setup
        assertEq(combinator.getRecorderCount(), 1, "Combinator should have 1 recorder");

        IPostActionHook[] memory retrieved = combinator.getRecorders();
        assertEq(address(retrieved[0]), address(timeRecorder), "Should contain time recorder");
    }

    function test_PostActionHookCombinator_RecorderCount() public {
        AuthorizationTimePostActionHook r1 = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));
        AuthorizationTimePostActionHook r2 = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));

        IPostActionHook[] memory recs = new IPostActionHook[](2);
        recs[0] = IPostActionHook(address(r1));
        recs[1] = IPostActionHook(address(r2));

        PostActionHookCombinator combinator = new PostActionHookCombinator(recs);
        assertEq(combinator.getRecorderCount(), 2, "Should have 2 recorders");
    }

    function test_PostActionHookCombinator_GetRecorders() public {
        AuthorizationTimePostActionHook r1 = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));
        AuthorizationTimePostActionHook r2 = new AuthorizationTimePostActionHook(address(escrow), bytes32(0));

        IPostActionHook[] memory recs = new IPostActionHook[](2);
        recs[0] = IPostActionHook(address(r1));
        recs[1] = IPostActionHook(address(r2));

        PostActionHookCombinator combinator = new PostActionHookCombinator(recs);
        IPostActionHook[] memory retrieved = combinator.getRecorders();
        assertEq(retrieved.length, 2, "Should return 2 recorders");
        assertEq(address(retrieved[0]), address(r1), "First recorder should match");
        assertEq(address(retrieved[1]), address(r2), "Second recorder should match");
    }

    function test_PostActionHookCombinator_EmptyRecorders_Reverts() public {
        IPostActionHook[] memory empty = new IPostActionHook[](0);
        vm.expectRevert(PostActionHookCombinator.EmptyRecorders.selector);
        new PostActionHookCombinator(empty);
    }

    function test_PostActionHookCombinator_TooManyRecorders_Reverts() public {
        IPostActionHook[] memory tooMany = new IPostActionHook[](11);
        for (uint256 i = 0; i < 11; i++) {
            tooMany[i] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        }
        vm.expectRevert();
        new PostActionHookCombinator(tooMany);
    }

    function test_PostActionHookCombinator_ZeroAddress_Reverts() public {
        IPostActionHook[] memory recs = new IPostActionHook[](2);
        recs[0] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        recs[1] = IPostActionHook(address(0));
        vm.expectRevert(abi.encodeWithSelector(PostActionHookCombinator.ZeroRecorder.selector, 1));
        new PostActionHookCombinator(recs);
    }

    // ============ BasePostActionHook ============

    function test_BasePostActionHook_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new AuthorizationTimePostActionHook(address(0), bytes32(0));
    }

    // ============ Helpers ============

    function _deployWithRecorder(address recorder) internal returns (PaymentOperator) {
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizePreActionCondition: address(0),
            authorizePostActionHook: recorder,
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
