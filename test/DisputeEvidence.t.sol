// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DisputeEvidence} from "../src/evidence/DisputeEvidence.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticAddressCondition} from "../src/plugins/conditions/access/static-address/StaticAddressCondition.sol";
import {SubmitterRole} from "../src/evidence/types/Types.sol";
import {EmptyCid, RefundRequestRequired, NotPayerReceiverOrArbiter} from "../src/evidence/types/Errors.sol";
import {InvalidOperator} from "../src/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract DisputeEvidenceTest is Test {
    DisputeEvidence public disputeEvidence;
    RefundRequest public refundRequest;
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    StaticAddressCondition public designatedAddressCondition;

    // Operator with no arbiter condition (address(0))
    PaymentOperator public operatorNoArbiter;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public designatedAddress; // arbiter
    address public payer;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        designatedAddress = makeAddr("designatedAddress");
        payer = makeAddr("payer");

        // Deploy real escrow
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");

        // Deploy PreApprovalPaymentCollector
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy designated address condition for arbiter
        designatedAddressCondition = new StaticAddressCondition(designatedAddress);

        // Deploy protocol fee config (no fees)
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);

        // Deploy operator factory
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        // Deploy operator WITH arbiter condition
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(designatedAddressCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Deploy operator WITHOUT arbiter condition (address(0))
        PaymentOperatorFactory.OperatorConfig memory configNoArbiter = PaymentOperatorFactory.OperatorConfig({
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
        operatorNoArbiter = PaymentOperator(operatorFactory.deployOperator(configNoArbiter));

        // Deploy refund request and evidence contracts
        refundRequest = new RefundRequest();
        disputeEvidence = new DisputeEvidence(address(refundRequest));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);

        vm.prank(receiver);
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
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(0),
            maxFeeBps: uint16(0),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _createPaymentInfoNoArbiter() internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operatorNoArbiter),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(0),
            maxFeeBps: uint16(0),
            feeReceiver: address(operatorNoArbiter),
            salt: 99999
        });
    }

    function _authorizeAndRequestRefund() internal returns (AuthCaptureEscrow.PaymentInfo memory paymentInfo) {
        paymentInfo = _createPaymentInfo();

        // Pre-approve and authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Create refund request
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function _authorizeAndRequestRefundNoArbiter() internal returns (AuthCaptureEscrow.PaymentInfo memory paymentInfo) {
        paymentInfo = _createPaymentInfoNoArbiter();

        // Pre-approve and authorize
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operatorNoArbiter.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Create refund request
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    // ============ submitEvidence Tests ============

    function test_submitEvidence_payer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmPayerEvidence123");

        DisputeEvidence.Evidence memory ev = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        assertEq(ev.submitter, payer);
        assertEq(uint256(ev.role), uint256(SubmitterRole.Payer));
        assertEq(ev.timestamp, uint48(block.timestamp));
        assertEq(ev.cid, "QmPayerEvidence123");
    }

    function test_submitEvidence_receiver() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(receiver);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmReceiverEvidence456");

        DisputeEvidence.Evidence memory ev = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        assertEq(ev.submitter, receiver);
        assertEq(uint256(ev.role), uint256(SubmitterRole.Receiver));
        assertEq(ev.cid, "QmReceiverEvidence456");
    }

    function test_submitEvidence_arbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(designatedAddress);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmArbiterEvidence789");

        DisputeEvidence.Evidence memory ev = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        assertEq(ev.submitter, designatedAddress);
        assertEq(uint256(ev.role), uint256(SubmitterRole.Arbiter));
        assertEq(ev.cid, "QmArbiterEvidence789");
    }

    function test_submitEvidence_unauthorized() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        address randomAddress = makeAddr("random");
        vm.prank(randomAddress);
        vm.expectRevert(NotPayerReceiverOrArbiter.selector);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmUnauthorized");
    }

    function test_submitEvidence_emptyCid() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(payer);
        vm.expectRevert(EmptyCid.selector);
        disputeEvidence.submitEvidence(paymentInfo, 0, "");
    }

    function test_submitEvidence_noRefundRequest() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        // Authorize but don't create refund request
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        vm.expectRevert(RefundRequestRequired.selector);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmNoRefund");
    }

    function test_submitEvidence_appendOnly() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        // Submit 3 evidence entries
        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmFirst");

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmSecond");

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmThird");

        // Verify count incremented correctly
        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 3);

        // Verify each entry
        DisputeEvidence.Evidence memory ev0 = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        DisputeEvidence.Evidence memory ev1 = disputeEvidence.getEvidence(paymentInfo, 0, 1);
        DisputeEvidence.Evidence memory ev2 = disputeEvidence.getEvidence(paymentInfo, 0, 2);

        assertEq(ev0.cid, "QmFirst");
        assertEq(ev1.cid, "QmSecond");
        assertEq(ev2.cid, "QmThird");
    }

    // ============ View Function Tests ============

    function test_getEvidence() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.warp(block.timestamp + 100);

        vm.prank(receiver);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmViewTest");

        DisputeEvidence.Evidence memory ev = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        assertEq(ev.submitter, receiver);
        assertEq(uint256(ev.role), uint256(SubmitterRole.Receiver));
        assertEq(ev.timestamp, uint48(block.timestamp));
        assertEq(ev.cid, "QmViewTest");
    }

    function test_getEvidence_revertsOutOfBounds() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.expectRevert(DisputeEvidence.IndexOutOfBounds.selector);
        disputeEvidence.getEvidence(paymentInfo, 0, 0);
    }

    function test_getEvidenceBatch() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        // Submit 5 evidence entries
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(payer);
            disputeEvidence.submitEvidence(
                paymentInfo, 0, string(abi.encodePacked("QmEvidence", bytes1(uint8(48 + i))))
            );
        }

        // Get first 3
        (DisputeEvidence.Evidence[] memory entries, uint256 total) =
            disputeEvidence.getEvidenceBatch(paymentInfo, 0, 0, 3);
        assertEq(total, 5);
        assertEq(entries.length, 3);

        // Get remaining 2
        (DisputeEvidence.Evidence[] memory entries2, uint256 total2) =
            disputeEvidence.getEvidenceBatch(paymentInfo, 0, 3, 3);
        assertEq(total2, 5);
        assertEq(entries2.length, 2);
    }

    function test_getEvidenceBatch_offsetBeyondTotal() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmSingle");

        (DisputeEvidence.Evidence[] memory entries, uint256 total) =
            disputeEvidence.getEvidenceBatch(paymentInfo, 0, 10, 5);
        assertEq(total, 1);
        assertEq(entries.length, 0);
    }

    function test_getEvidenceBatch_zeroCount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmSingle");

        (DisputeEvidence.Evidence[] memory entries, uint256 total) =
            disputeEvidence.getEvidenceBatch(paymentInfo, 0, 0, 0);
        assertEq(total, 1);
        assertEq(entries.length, 0);
    }

    function test_getEvidenceCount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 0);

        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmOne");
        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 1);

        vm.prank(receiver);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmTwo");
        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 2);
    }

    // ============ Arbiter Edge Cases ============

    function test_arbiter_noCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefundNoArbiter();

        // Payer and receiver should still work
        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmPayerOk");

        vm.prank(receiver);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmReceiverOk");

        // Designated address is NOT arbiter here (no condition configured)
        vm.prank(designatedAddress);
        vm.expectRevert(NotPayerReceiverOrArbiter.selector);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmShouldFail");

        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 2);
    }

    // ============ Multi-Party Test ============

    function test_multipleParties() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorizeAndRequestRefund();

        // All three parties submit evidence
        vm.prank(payer);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmPayerClaim");

        vm.prank(receiver);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmReceiverResponse");

        vm.prank(designatedAddress);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmArbiterAnalysis");

        // Verify count
        assertEq(disputeEvidence.getEvidenceCount(paymentInfo, 0), 3);

        // Verify roles are correct
        DisputeEvidence.Evidence memory ev0 = disputeEvidence.getEvidence(paymentInfo, 0, 0);
        DisputeEvidence.Evidence memory ev1 = disputeEvidence.getEvidence(paymentInfo, 0, 1);
        DisputeEvidence.Evidence memory ev2 = disputeEvidence.getEvidence(paymentInfo, 0, 2);

        assertEq(uint256(ev0.role), uint256(SubmitterRole.Payer));
        assertEq(uint256(ev1.role), uint256(SubmitterRole.Receiver));
        assertEq(uint256(ev2.role), uint256(SubmitterRole.Arbiter));

        assertEq(ev0.submitter, payer);
        assertEq(ev1.submitter, receiver);
        assertEq(ev2.submitter, designatedAddress);
    }

    // ============ Operator Validation ============

    function test_submitEvidence_revertsZeroOperator() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0);

        vm.prank(payer);
        vm.expectRevert(InvalidOperator.selector);
        disputeEvidence.submitEvidence(paymentInfo, 0, "QmBadOperator");
    }
}
