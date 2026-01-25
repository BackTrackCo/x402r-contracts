// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {InvalidOperator} from "../src/commerce-payments/types/Errors.sol";
import {ConditionNotMet} from "../src/commerce-payments/operator/types/Errors.sol";
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
    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    // Events from operator
    event AuthorizationCreated(
        bytes32 indexed paymentInfoHash,
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
    );

    event ReleaseExecuted(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 amount, uint256 timestamp);

    event RefundExecuted(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer, uint256 amount);

    event ChargeExecuted(
        bytes32 indexed paymentInfoHash,
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
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
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        // Deploy operator via factory with release condition
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = ArbitrationOperator(factory.deployOperator(config));

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

    function _createSimpleConfig(address _arbiter)
        internal
        pure
        returns (ArbitrationOperatorFactory.OperatorConfig memory)
    {
        return ArbitrationOperatorFactory.OperatorConfig({
            arbiter: _arbiter,
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
    }

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
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        address deployedOperator = factory.getOperator(config);
        assertEq(deployedOperator, address(operator));
    }

    function test_Factory_IdempotentDeploy() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        address first = factory.deployOperator(config);
        address second = factory.deployOperator(config);
        assertEq(first, second);
    }

    function test_Factory_DifferentArbitersDifferentOperators() public {
        address arbiter2 = makeAddr("arbiter2");
        ArbitrationOperatorFactory.OperatorConfig memory config1 = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        ArbitrationOperatorFactory.OperatorConfig memory config2 = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter2,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        address op1 = factory.deployOperator(config1);
        address op2 = factory.deployOperator(config2);
        assertTrue(op1 != op2);
    }

    function test_Factory_DifferentConditionsDifferentOperators() public {
        MockReleaseCondition condition2 = new MockReleaseCondition();
        ArbitrationOperatorFactory.OperatorConfig memory config1 = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        ArbitrationOperatorFactory.OperatorConfig memory config2 = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(condition2),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        address op1 = factory.deployOperator(config1);
        address op2 = factory.deployOperator(config2);
        assertTrue(op1 != op2);
    }

    function test_Factory_OperatorOwnerIsFactoryOwner() public {
        MockReleaseCondition newCondition = new MockReleaseCondition();
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: makeAddr("newArbiter"),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(newCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        address newOperator = factory.deployOperator(config);
        assertEq(ArbitrationOperator(newOperator).owner(), owner);
    }

    function test_Factory_DeploySimpleOperator() public {
        // Deploy operator with zero conditions (most permissive)
        address op = factory.deployOperator(_createSimpleConfig(arbiter));
        ArbitrationOperator defaultOp = ArbitrationOperator(op);

        // Verify all conditions are zero
        assertEq(address(defaultOp.AUTHORIZE_CONDITION()), address(0));
        assertEq(address(defaultOp.RELEASE_CONDITION()), address(0));
        assertEq(address(defaultOp.REFUND_IN_ESCROW_CONDITION()), address(0));
        assertEq(address(defaultOp.REFUND_POST_ESCROW_CONDITION()), address(0));
    }

    // ============ Authorization Tests ============

    function test_Authorize_Success() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");

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
        operator.authorize(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");
    }

    // ============ Charge Tests ============

    function test_Charge_Success() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.salt = 99999; // Different salt to avoid collision with authorize tests
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        uint256 fee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;

        vm.expectEmit(true, true, true, true, address(operator));
        emit ChargeExecuted(paymentInfoHash, payer, receiver, PAYMENT_AMOUNT, block.timestamp);

        operator.charge(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");

        // Check payment was recorded in operator
        assertTrue(operator.paymentExists(paymentInfoHash));

        // Check receiver got tokens minus fee (charge goes directly to receiver)
        assertEq(token.balanceOf(receiver), receiverBalanceBefore + PAYMENT_AMOUNT - fee);

        // Check escrow state - charge() goes directly to receiver, so capturable=0, refundable=amount
        (bool hasCollected, uint120 capturable, uint120 refundable) = escrow.paymentState(paymentInfoHash);
        assertTrue(hasCollected);
        assertEq(capturable, 0); // No escrow hold
        assertEq(refundable, PAYMENT_AMOUNT); // Can be refunded
    }

    function test_Charge_RevertsOnInvalidOperator() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(0x1234); // Wrong operator

        vm.expectRevert(InvalidOperator.selector);
        operator.charge(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");
    }

    function test_Charge_RevertsOnInvalidFeeBps() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.minFeeBps = 0; // Wrong fee

        vm.expectRevert();
        operator.charge(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");
    }

    function test_Charge_RevertsOnInvalidFeeReceiver() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.feeReceiver = address(0x1234); // Wrong fee receiver

        vm.expectRevert();
        operator.charge(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");
    }

    function test_Charge_RecordsPayerAndReceiverPayments() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.salt = 88888;
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        operator.charge(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");

        // Check payer payments tracking
        bytes32[] memory payerPayments = operator.getPayerPayments(payer);
        bool found = false;
        for (uint256 i = 0; i < payerPayments.length; i++) {
            if (payerPayments[i] == paymentInfoHash) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Payment should be tracked for payer");

        // Check receiver payments tracking
        bytes32[] memory receiverPayments = operator.getReceiverPayments(receiver);
        found = false;
        for (uint256 i = 0; i < receiverPayments.length; i++) {
            if (receiverPayments[i] == paymentInfoHash) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Payment should be tracked for receiver");
    }

    // ============ Release Tests ============

    function test_Release_Success() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        // Approve the release via condition contract (using PaymentInfo)
        releaseCondition.approvePayment(paymentInfo);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        // Pull model: call release on the operator directly
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

    function test_Release_ByAnyone() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);

        releaseCondition.approvePayment(paymentInfo);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        uint256 fee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;

        // Pull model: anyone can call release on operator - funds still go to receiver
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        assertEq(token.balanceOf(receiver), receiverBalanceBefore + PAYMENT_AMOUNT - fee);
    }

    function test_Release_RevertsWhenConditionNotMet() public {
        (, MockEscrow.PaymentInfo memory enforcedInfo) = _authorize();
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(enforcedInfo);

        // Do NOT approve - condition should block release
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
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
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Refund (PartialVoid) Tests ============
    // Note: Refund tests use a permissive operator (all conditions = address(0))
    // Access control for refunds should be tested in specific condition implementations

    function test_Refund_Success() public {
        // Deploy permissive operator for refund testing
        ArbitrationOperator permissiveOperator =
            ArbitrationOperator(factory.deployOperator(_createSimpleConfig(arbiter)));

        MockEscrow.PaymentInfo memory paymentInfo = MockEscrow.PaymentInfo({
            operator: address(permissiveOperator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(permissiveOperator),
            salt: 12345
        });
        AuthCaptureEscrow.PaymentInfo memory authPaymentInfo = _toAuthCapturePaymentInfo(paymentInfo);

        permissiveOperator.authorize(authPaymentInfo, PAYMENT_AMOUNT, address(0), "");
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint120 refundAmount = uint120(PAYMENT_AMOUNT / 2);

        vm.prank(receiver);
        vm.expectEmit(true, false, false, true, address(permissiveOperator));
        emit RefundExecuted(authPaymentInfo, authPaymentInfo.payer, refundAmount);
        permissiveOperator.refundInEscrow(authPaymentInfo, refundAmount);

        // Check payer got refund
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);

        // Check escrow state
        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - refundAmount);
    }

    function test_Refund_MultiplePartial() public {
        // Deploy permissive operator for refund testing
        ArbitrationOperator permissiveOperator =
            ArbitrationOperator(factory.deployOperator(_createSimpleConfig(arbiter)));

        MockEscrow.PaymentInfo memory paymentInfo = MockEscrow.PaymentInfo({
            operator: address(permissiveOperator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(permissiveOperator),
            salt: 12348
        });
        AuthCaptureEscrow.PaymentInfo memory authPaymentInfo = _toAuthCapturePaymentInfo(paymentInfo);

        permissiveOperator.authorize(authPaymentInfo, PAYMENT_AMOUNT, address(0), "");
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        uint120 firstRefund = uint120(PAYMENT_AMOUNT / 3);
        uint120 secondRefund = uint120(PAYMENT_AMOUNT / 3);

        vm.prank(receiver);
        permissiveOperator.refundInEscrow(authPaymentInfo, firstRefund);

        vm.prank(arbiter);
        permissiveOperator.refundInEscrow(authPaymentInfo, secondRefund);

        (, uint120 capturable,) = escrow.paymentState(paymentInfoHash);
        assertEq(capturable, PAYMENT_AMOUNT - firstRefund - secondRefund);
    }

    // ============ Fee Management Tests ============

    function test_SetFeesEnabled_OnlyOwner() public {
        // Queue the change
        operator.queueFeesEnabled(true);
        assertFalse(operator.feesEnabled()); // Not yet active

        // Warp past timelock
        vm.warp(block.timestamp + operator.TIMELOCK_DELAY());

        // Execute the change
        operator.executeFeesEnabled();
        assertTrue(operator.feesEnabled());

        // Queue disable
        operator.queueFeesEnabled(false);
        vm.warp(block.timestamp + operator.TIMELOCK_DELAY());
        operator.executeFeesEnabled();
        assertFalse(operator.feesEnabled());
    }

    function test_SetFeesEnabled_RevertsOnNotOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        operator.queueFeesEnabled(true);
    }

    function test_SetFeesEnabled_TimelockNotElapsed() public {
        operator.queueFeesEnabled(true);

        // Try to execute before timelock - should revert
        vm.expectRevert();
        operator.executeFeesEnabled();
    }

    function test_SetFeesEnabled_CancelPending() public {
        operator.queueFeesEnabled(true);

        // Cancel the pending change
        operator.cancelFeesEnabled();

        // Try to execute - should revert (no pending change)
        vm.expectRevert();
        operator.executeFeesEnabled();
    }

    function test_DistributeFees_ProtocolDisabled() public {
        // Setup tokens in operator
        uint256 feeAmount = 1000 * 10 ** 18;
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
        // Enable fees via timelock
        operator.queueFeesEnabled(true);
        vm.warp(block.timestamp + operator.TIMELOCK_DELAY());
        operator.executeFeesEnabled();
        assertTrue(operator.feesEnabled());

        uint256 feeAmount = 1000 * 10 ** 18;
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
