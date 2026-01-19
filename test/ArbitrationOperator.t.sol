// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/ArbitrationOperator.sol";
import {ArbitrationOperatorAccess} from "../src/commerce-payments/operator/ArbitrationOperatorAccess.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {InvalidOperator, NotReceiver, NotPayer, NotReceiverOrArbiter, RefundPeriodNotPassed} from "../src/commerce-payments/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ArbitrationOperatorTest is Test {
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public factory;
    MockERC20 public token;
    MockEscrow public escrow;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver; // merchant
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50; // 0.5%
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25; // 25%
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;
    uint48 public constant REFUND_PERIOD = 7 days; // Set at operator deployment

    // Events from operator
    event AuthorizationCreated(
        bytes32 indexed paymentInfoHash,
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
    );

    event CaptureExecuted(
        bytes32 indexed paymentInfoHash,
        uint256 amount,
        uint256 timestamp
    );

    event PartialVoidExecuted(
        bytes32 indexed paymentInfoHash,
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

        // Deploy factory (owner controls fee settings on all operators)
        factory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory (factory owner becomes operator owner)
        operator = ArbitrationOperator(factory.deployOperator(arbiter, REFUND_PERIOD));

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
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days), // Will be overridden by operator
            minFeeBps: 0,
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(0),
            salt: 12345
        });
    }

    // Helper to get the actual enforced PaymentInfo that the operator uses
    function _getEnforcedPaymentInfo(MockEscrow.PaymentInfo memory original)
        internal
        view
        returns (MockEscrow.PaymentInfo memory)
    {
        MockEscrow.PaymentInfo memory enforced = original;
        enforced.authorizationExpiry = type(uint48).max;
        enforced.refundExpiry = type(uint48).max; // Operator overrides to satisfy base escrow validation
        enforced.feeReceiver = address(operator);

        // Always expect MAX_TOTAL_FEE_RATE
        enforced.minFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        enforced.maxFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        return enforced;
    }

    function _authorize() internal returns (bytes32, MockEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0), // tokenCollector (mock doesn't use it)
            ""
        );

        // Get the enforced info which matches what the operator actually used
        MockEscrow.PaymentInfo memory enforcedInfo = _getEnforcedPaymentInfo(paymentInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        return (paymentInfoHash, enforcedInfo);
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
        assertEq(operator.REFUND_PERIOD(), REFUND_PERIOD);
        assertEq(operator.feesEnabled(), false);
        assertEq(operator.owner(), owner);
    }

    // ============ Factory Tests ============

    function test_Factory_DeploysOperator() public view {
        address deployedOperator = factory.getOperator(arbiter, REFUND_PERIOD);
        assertEq(deployedOperator, address(operator));
    }

    function test_Factory_IdempotentDeploy() public {
        address first = factory.deployOperator(arbiter, REFUND_PERIOD);
        address second = factory.deployOperator(arbiter, REFUND_PERIOD);
        assertEq(first, second);
    }

    function test_Factory_DifferentArbitersDifferentOperators() public {
        address arbiter2 = makeAddr("arbiter2");
        address op1 = factory.deployOperator(arbiter, REFUND_PERIOD);
        address op2 = factory.deployOperator(arbiter2, REFUND_PERIOD);
        assertTrue(op1 != op2);
    }

    function test_Factory_DifferentRefundPeriodsDifferentOperators() public {
        uint48 refundPeriod2 = 14 days;
        address op1 = factory.deployOperator(arbiter, REFUND_PERIOD);
        address op2 = factory.deployOperator(arbiter, refundPeriod2);
        assertTrue(op1 != op2);
    }

    function test_Factory_OperatorOwnerIsFactoryOwner() public {
        address newOperator = factory.deployOperator(makeAddr("newArbiter"), REFUND_PERIOD);
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

        // We expect the operator to have enforced specific params
        MockEscrow.PaymentInfo memory enforcedInfo = _getEnforcedPaymentInfo(paymentInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        // Check escrow state
        (bool hasCollected, uint120 capturable, uint120 refundable) = escrow.paymentState(paymentInfoHash);
        assertTrue(hasCollected);
        assertEq(capturable, PAYMENT_AMOUNT);
        assertEq(refundable, 0);

        // Check operator tracked the payment
        assertTrue(operator.paymentExists(paymentInfoHash));
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

    // ============ Release (Capture) Tests ============

    function test_Release_Success() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        // Fast forward past refund period
        vm.warp(block.timestamp + REFUND_PERIOD + 1);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(receiver);
        operator.release(
            paymentInfoHash,
            PAYMENT_AMOUNT
        );

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
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();
        vm.warp(block.timestamp + REFUND_PERIOD + 1);

        vm.expectRevert(NotReceiver.selector);
        operator.release(
            paymentInfoHash,
            PAYMENT_AMOUNT
        );
    }

    function test_Release_RevertsOnRefundPeriodNotPassed() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(receiver);
        vm.expectRevert(RefundPeriodNotPassed.selector);
        operator.release(
            paymentInfoHash,
            PAYMENT_AMOUNT
        );
    }

    // ============ Early Release Tests ============

    function test_EarlyRelease_Success() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        // Do NOT fast forward (time is still before refund period ends)

        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(payer);
        operator.earlyRelease(
            paymentInfoHash,
            PAYMENT_AMOUNT
        );

        // Check receiver got the tokens MINUS fees
        uint256 fee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;
        assertEq(token.balanceOf(receiver), receiverBalanceBefore + PAYMENT_AMOUNT - fee);

        // Check escrow state updated
        (, uint120 capturable, uint120 refundable) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, 0);
        assertEq(refundable, PAYMENT_AMOUNT);
    }

    function test_EarlyRelease_RevertsOnNotPayer() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        operator.earlyRelease(
            paymentInfoHash,
            PAYMENT_AMOUNT
        );
    }

    // ============ Refund (PartialVoid) Tests ============

    function test_Refund_ByReceiver() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(receiver);
        operator.refund(
            paymentInfoHash,
            refundAmount
        );

        // Check payer got refund
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);

        // Check escrow state
        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount);
    }

    function test_Refund_ByArbiter() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(arbiter);
        operator.refund(
            paymentInfoHash,
            refundAmount
        );

        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);

        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount);
    }

    function test_Refund_RevertsOnNotReceiverOrArbiter() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(payer);
        vm.expectRevert(NotReceiverOrArbiter.selector);
        operator.refund(
            paymentInfoHash,
            uint120(PAYMENT_AMOUNT / 2)
        );
    }

    function test_Refund_MultiplePartial() public {
        (bytes32 paymentInfoHash, MockEscrow.PaymentInfo memory paymentInfo) = _authorize();

        uint120 firstRefund = uint120(PAYMENT_AMOUNT / 3);
        uint120 secondRefund = uint120(PAYMENT_AMOUNT / 3);

        vm.prank(receiver);
        operator.refund(paymentInfoHash, firstRefund);

        vm.prank(arbiter);
        operator.refund(paymentInfoHash, secondRefund);

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

        uint256 operatorBalanceBefore = token.balanceOf(address(operator));
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

        uint256 operatorBalanceBefore = token.balanceOf(address(operator));
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
