// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {InvalidOperator, NotReceiver, NotPayer, NotReceiverOrArbiter} from "../src/commerce-payments/types/Errors.sol";
import {ReleaseLocked} from "../src/commerce-payments/operator/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";


contract ArbitrationOperatorTest is Test {
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public factory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver; // merchant
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50; // 0.5%
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25; // 25%
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;

    // Events from operator
    event AuthorizationCreated(
        bytes32 indexed paymentInfoHash,
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
    );

    event ReleaseExecuted(
        AuthCaptureEscrow.PaymentInfo paymentInfo,
        uint256 amount,
        uint256 timestamp
    );

    event RefundExecuted(
        AuthCaptureEscrow.PaymentInfo paymentInfo,
        address indexed payer,
        uint256 amount
    );

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        releaseCondition = new MockReleaseCondition();

        // Deploy factory (owner controls fee settings on all operators)
        factory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory (factory owner becomes operator owner)
        operator = ArbitrationOperator(factory.deployOperator(arbiter, address(releaseCondition)));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        // Approve escrow to spend tokens
        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);

        // Approve escrow for receiver (needed for post-capture refunds)
        vm.prank(receiver);
        token.approve(address(escrow), type(uint256).max);
    }

    // ============ Helper Functions ============

    function _createPaymentInfo() internal view returns (MockEscrow.PaymentInfo memory) {
        return MockEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _authorize() internal returns (bytes32, MockEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0), // tokenCollector (mock doesn't use it)
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, paymentInfo);
    }

    // Convert MockEscrow.PaymentInfo to AuthCaptureEscrow.PaymentInfo
    function _toAuthCapturePaymentInfo(MockEscrow.PaymentInfo memory mockInfo)
        internal
        pure
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: mockInfo.operator,
            payer: mockInfo.payer,
            receiver: mockInfo.receiver,
            token: mockInfo.token,
            maxAmount: mockInfo.maxAmount,
            preApprovalExpiry: mockInfo.preApprovalExpiry,
            authorizationExpiry: mockInfo.authorizationExpiry,
            refundExpiry: mockInfo.refundExpiry,
            minFeeBps: mockInfo.minFeeBps,
            maxFeeBps: mockInfo.maxFeeBps,
            feeReceiver: mockInfo.feeReceiver,
            salt: mockInfo.salt
        });
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(address(operator.ESCROW()), address(escrow));
        assertEq(operator.ARBITER(), arbiter);
        assertEq(operator.MAX_TOTAL_FEE_RATE(), MAX_TOTAL_FEE_RATE);
        assertEq(operator.PROTOCOL_FEE_PERCENTAGE(), PROTOCOL_FEE_PERCENTAGE);
        assertEq(address(operator.RELEASE_CONDITION()), address(releaseCondition));
        assertEq(operator.feesEnabled(), false);
        assertEq(operator.owner(), owner);
    }

    // ============ Factory Tests ============

    function test_Factory_DeploysOperator() public view {
        address deployedOperator = factory.getOperator(arbiter, address(releaseCondition));
        assertEq(deployedOperator, address(operator));
    }

    function test_Factory_IdempotentDeploy() public {
        address first = factory.deployOperator(arbiter, address(releaseCondition));
        address second = factory.deployOperator(arbiter, address(releaseCondition));
        assertEq(first, second);
    }

    function test_Factory_DifferentArbitersDifferentOperators() public {
        address arbiter2 = makeAddr("arbiter2");
        address op1 = factory.deployOperator(arbiter, address(releaseCondition));
        address op2 = factory.deployOperator(arbiter2, address(releaseCondition));
        assertTrue(op1 != op2);
    }

    function test_Factory_DifferentConditionsDifferentOperators() public {
        MockReleaseCondition condition2 = new MockReleaseCondition();
        address op1 = factory.deployOperator(arbiter, address(releaseCondition));
        address op2 = factory.deployOperator(arbiter, address(condition2));
        assertTrue(op1 != op2);
    }

    function test_Factory_OperatorOwnerIsFactoryOwner() public {
        MockReleaseCondition newCondition = new MockReleaseCondition();
        address newOperator = factory.deployOperator(makeAddr("newArbiter"), address(newCondition));
        assertEq(ArbitrationOperator(newOperator).owner(), owner);
    }

    // ============ Authorization Tests ============

    function test_Authorize_Success() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Check escrow state
        (bool hasCollected, uint120 capturable, uint120 refundable) = escrow.paymentState(paymentInfoHash);
        assertTrue(hasCollected);
        assertEq(capturable, PAYMENT_AMOUNT);
        assertEq(refundable, 0);
    }

    function test_Authorize_RevertsOnInvalidOperator() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0x1234); // Wrong operator

        vm.expectRevert(InvalidOperator.selector);
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
    }

    // ============ Release Tests ============

    function test_Release_Success() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        // Approve the release via condition contract (using PaymentInfo)
        releaseCondition.approvePayment(paymentInfo);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(receiver);
        vm.expectEmit(false, false, false, true, address(operator));
        emit ReleaseExecuted(paymentInfo, PAYMENT_AMOUNT, block.timestamp);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // Check receiver got the tokens MINUS fees
        // Always MAX_TOTAL_FEE_RATE (50 bps)
        // 1000 * 10^18 * 50 / 10000 = 5 * 10^18
        uint256 fee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;

        assertEq(token.balanceOf(receiver), receiverBalanceBefore + PAYMENT_AMOUNT - fee);

        // Check escrow state updated
        (, uint120 capturable, uint120 refundable) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, 0);
        assertEq(refundable, PAYMENT_AMOUNT);
    }

    function test_Release_RevertsOnNotReceiver() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);

        releaseCondition.approvePayment(paymentInfo);

        vm.expectRevert(NotReceiver.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_RevertsWhenConditionNotMet() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);

        // Do NOT approve - condition should block release

        vm.prank(receiver);
        vm.expectRevert(ReleaseLocked.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_RevertsAfterConditionRevoked() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));

        // Approve then revoke
        releaseCondition.approvePayment(paymentInfo);
        releaseCondition.revoke(paymentInfoHash);

        vm.prank(receiver);
        vm.expectRevert(ReleaseLocked.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Refund (PartialVoid) Tests ============

    function test_Refund_ByReceiver() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(receiver);
        vm.expectEmit(true, false, false, true, address(operator));
        emit RefundExecuted(paymentInfo, paymentInfo.payer, refundAmount);
        operator.escrowRefund(paymentInfo, refundAmount);

        // Check payer got refund
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);

        // Check escrow state
        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount);
    }

    function test_Refund_ByArbiter() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(arbiter);
        operator.escrowRefund(paymentInfo, refundAmount);

        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);

        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount);
    }

    function test_Refund_RevertsOnNotReceiverOrArbiter() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);

        vm.prank(payer);
        vm.expectRevert(NotReceiverOrArbiter.selector);
        operator.escrowRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2));
    }

    function test_Refund_MultiplePartial() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        uint120 firstRefund = uint120(PAYMENT_AMOUNT / 3);
        uint120 secondRefund = uint120(PAYMENT_AMOUNT / 3);

        vm.prank(receiver);
        operator.escrowRefund(paymentInfo, firstRefund);

        vm.prank(arbiter);
        operator.escrowRefund(paymentInfo, secondRefund);

        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - firstRefund - secondRefund);
    }

    // ============ Fee Management Tests ============

    function test_SetFeesEnabled_OnlyOwner() public {
        operator.setFeesEnabled(true);
        assertTrue(operator.feesEnabled());

        operator.setFeesEnabled(false);
        assertFalse(operator.feesEnabled());
    }

    function test_SetFeesEnabled_RevertsOnNotOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        operator.setFeesEnabled(true);
    }

    function test_DistributeFees_ProtocolDisabled() public {
        // Setup tokens in operator
        uint256 feeAmount = 1000 * 10**18;
        token.mint(address(operator), feeAmount);

        // Protocol fees are disabled by default
        assertFalse(operator.feesEnabled());

        uint256 arbiterBalanceBefore = token.balanceOf(arbiter);
        uint256 protocolBalanceBefore = token.balanceOf(protocolFeeRecipient);

        operator.distributeFees(address(token));

        // Checks
        assertEq(token.balanceOf(address(operator)), 0);
        assertEq(token.balanceOf(arbiter), arbiterBalanceBefore + feeAmount);
        assertEq(token.balanceOf(protocolFeeRecipient), protocolBalanceBefore); // Should get nothing
    }

    function test_DistributeFees_ProtocolEnabled() public {
        operator.setFeesEnabled(true);
        assertTrue(operator.feesEnabled());

        uint256 feeAmount = 1000 * 10**18;
        token.mint(address(operator), feeAmount);

        uint256 arbiterBalanceBefore = token.balanceOf(arbiter);
        uint256 protocolBalanceBefore = token.balanceOf(protocolFeeRecipient);

        operator.distributeFees(address(token));

        uint256 expectedProtocol = (feeAmount * PROTOCOL_FEE_PERCENTAGE) / 100;
        uint256 expectedArbiter = feeAmount - expectedProtocol;

        assertEq(token.balanceOf(address(operator)), 0);
        assertEq(token.balanceOf(arbiter), arbiterBalanceBefore + expectedArbiter);
        assertEq(token.balanceOf(protocolFeeRecipient), protocolBalanceBefore + expectedProtocol);
    }
}
