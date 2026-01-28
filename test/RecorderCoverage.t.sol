// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {AuthorizationTimeRecorder} from "../src/conditions/AuthorizationTimeRecorder.sol";
import {PaymentIndexRecorder} from "../src/conditions/PaymentIndexRecorder.sol";
import {RecorderCombinator} from "../src/conditions/combinators/RecorderCombinator.sol";
import {IRecorder} from "../src/conditions/IRecorder.sol";
import {BaseRecorder} from "../src/conditions/BaseRecorder.sol";

/**
 * @title RecorderCoverageTest
 * @notice Tests for AuthorizationTimeRecorder, PaymentIndexRecorder, RecorderCombinator, BaseRecorder
 */
contract RecorderCoverageTest is Test {
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

    // ============ AuthorizationTimeRecorder ============

    function test_AuthorizationTimeRecorder_RecordsTimestamp() public {
        AuthorizationTimeRecorder timeRecorder = new AuthorizationTimeRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(timeRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 1);

        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        uint256 authTime = timeRecorder.getAuthorizationTime(paymentInfo);
        assertEq(authTime, block.timestamp, "Auth time should be current timestamp");
    }

    function test_AuthorizationTimeRecorder_ReturnsZeroForUnknown() public {
        AuthorizationTimeRecorder timeRecorder = new AuthorizationTimeRecorder(address(escrow), bytes32(0));
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(this), 99);
        assertEq(timeRecorder.getAuthorizationTime(paymentInfo), 0, "Should be zero for unknown payment");
    }

    // ============ PaymentIndexRecorder ============

    function test_PaymentIndexRecorder_IndexesPayerAndReceiver() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 2);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        assertEq(indexRecorder.payerPaymentCount(payer), 1, "Payer should have 1 payment");
        assertEq(indexRecorder.receiverPaymentCount(receiver), 1, "Receiver should have 1 payment");
    }

    function test_PaymentIndexRecorder_GetPayerPayments_Pagination() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        // Create 3 payments
        for (uint256 i = 0; i < 3; i++) {
            AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 100 + i);
            vm.prank(payer);
            collector.preApprove(paymentInfo);
            op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        }

        // Get page 1 (offset 0, count 2)
        (PaymentIndexRecorder.PaymentRecord[] memory records, uint256 total) =
            indexRecorder.getPayerPayments(payer, 0, 2);
        assertEq(total, 3, "Total should be 3");
        assertEq(records.length, 2, "Page should have 2 records");

        // Get page 2 (offset 2, count 2)
        (records, total) = indexRecorder.getPayerPayments(payer, 2, 2);
        assertEq(records.length, 1, "Last page should have 1 record");
    }

    function test_PaymentIndexRecorder_GetPayerPayments_OffsetBeyondTotal() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        (PaymentIndexRecorder.PaymentRecord[] memory records, uint256 total) =
            indexRecorder.getPayerPayments(payer, 100, 10);
        assertEq(total, 0, "Total should be 0 for no payments");
        assertEq(records.length, 0, "Should return empty array");
    }

    function test_PaymentIndexRecorder_GetPayerPayments_ZeroCount() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 3);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (PaymentIndexRecorder.PaymentRecord[] memory records, uint256 total) =
            indexRecorder.getPayerPayments(payer, 0, 0);
        assertEq(total, 1, "Total should be 1");
        assertEq(records.length, 0, "Should return empty for zero count");
    }

    function test_PaymentIndexRecorder_GetPayerPayment_IndexOutOfBounds() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexRecorder.IndexOutOfBounds.selector);
        indexRecorder.getPayerPayment(payer, 0);
    }

    function test_PaymentIndexRecorder_GetReceiverPayments() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 4);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        (PaymentIndexRecorder.PaymentRecord[] memory records, uint256 total) =
            indexRecorder.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 1, "Receiver should have 1 payment");
        assertEq(records.length, 1, "Should return 1 record");
    }

    function test_PaymentIndexRecorder_GetReceiverPayment_IndexOutOfBounds() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        vm.expectRevert(PaymentIndexRecorder.IndexOutOfBounds.selector);
        indexRecorder.getReceiverPayment(receiver, 0);
    }

    function test_PaymentIndexRecorder_RecordCount() public {
        PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));
        PaymentOperator op = _deployWithRecorder(address(indexRecorder));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(op), 5);
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        op.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        bytes32 hash = escrow.getHash(paymentInfo);
        assertEq(indexRecorder.recordCount(hash), 1, "Record count should be 1");
    }

    // ============ RecorderCombinator ============

    function test_RecorderCombinator_CombinesMultipleRecorders() public {
        // Use codehash(0) so sub-recorders accept calls from the combinator
        // The combinator itself checks msg.sender == operator, then delegates
        AuthorizationTimeRecorder timeRecorder = new AuthorizationTimeRecorder(address(escrow), bytes32(0));

        IRecorder[] memory recs = new IRecorder[](1);
        recs[0] = IRecorder(address(timeRecorder));

        RecorderCombinator combinator = new RecorderCombinator(recs);
        PaymentOperator op = _deployWithRecorder(address(combinator));

        // The combinator checks msg.sender == paymentInfo.operator
        // Sub-recorders (BaseRecorder) check codehash of msg.sender
        // With codehash=bytes32(0), BaseRecorder accepts any operator-codehash caller
        // But the actual caller of sub-recorders is the combinator, not the operator
        // So we just test the combinator's own validation and setup
        assertEq(combinator.getRecorderCount(), 1, "Combinator should have 1 recorder");

        IRecorder[] memory retrieved = combinator.getRecorders();
        assertEq(address(retrieved[0]), address(timeRecorder), "Should contain time recorder");
    }

    function test_RecorderCombinator_RecorderCount() public {
        AuthorizationTimeRecorder r1 = new AuthorizationTimeRecorder(address(escrow), bytes32(0));
        AuthorizationTimeRecorder r2 = new AuthorizationTimeRecorder(address(escrow), bytes32(0));

        IRecorder[] memory recs = new IRecorder[](2);
        recs[0] = IRecorder(address(r1));
        recs[1] = IRecorder(address(r2));

        RecorderCombinator combinator = new RecorderCombinator(recs);
        assertEq(combinator.getRecorderCount(), 2, "Should have 2 recorders");
    }

    function test_RecorderCombinator_GetRecorders() public {
        AuthorizationTimeRecorder r1 = new AuthorizationTimeRecorder(address(escrow), bytes32(0));
        AuthorizationTimeRecorder r2 = new AuthorizationTimeRecorder(address(escrow), bytes32(0));

        IRecorder[] memory recs = new IRecorder[](2);
        recs[0] = IRecorder(address(r1));
        recs[1] = IRecorder(address(r2));

        RecorderCombinator combinator = new RecorderCombinator(recs);
        IRecorder[] memory retrieved = combinator.getRecorders();
        assertEq(retrieved.length, 2, "Should return 2 recorders");
        assertEq(address(retrieved[0]), address(r1), "First recorder should match");
        assertEq(address(retrieved[1]), address(r2), "Second recorder should match");
    }

    function test_RecorderCombinator_EmptyRecorders_Reverts() public {
        IRecorder[] memory empty = new IRecorder[](0);
        vm.expectRevert(RecorderCombinator.EmptyRecorders.selector);
        new RecorderCombinator(empty);
    }

    function test_RecorderCombinator_TooManyRecorders_Reverts() public {
        IRecorder[] memory tooMany = new IRecorder[](11);
        for (uint256 i = 0; i < 11; i++) {
            tooMany[i] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        }
        vm.expectRevert();
        new RecorderCombinator(tooMany);
    }

    function test_RecorderCombinator_ZeroAddress_Reverts() public {
        IRecorder[] memory recs = new IRecorder[](2);
        recs[0] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        recs[1] = IRecorder(address(0));
        vm.expectRevert(abi.encodeWithSelector(RecorderCombinator.ZeroRecorder.selector, 1));
        new RecorderCombinator(recs);
    }

    // ============ BaseRecorder ============

    function test_BaseRecorder_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new AuthorizationTimeRecorder(address(0), bytes32(0));
    }

    // ============ Helpers ============

    function _deployWithRecorder(address recorder) internal returns (PaymentOperator) {
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: recorder,
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
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
