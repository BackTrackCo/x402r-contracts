// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EscrowPeriodCondition} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodConditionFactory} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";
import {
    PaymentAlreadyRegistered,
    NotPayer,
    InvalidEscrowPeriod
} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";

contract EscrowPeriodConditionTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockReleaseCondition public mockCondition; // Used for operator deployment

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;
    uint256 public constant ESCROW_PERIOD = 7 days;

    // Events
    event PaymentRegistered(bytes32 indexed paymentInfoHash, uint256 endTime);
    event PayerBypassTriggered(bytes32 indexed paymentInfoHash, address indexed payer);
    event EscrowPeriodConditionDeployed(address indexed condition, uint256 escrowPeriod);

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        mockCondition = new MockReleaseCondition();

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory (using mock condition initially)
        operator = ArbitrationOperator(operatorFactory.deployOperator(arbiter, address(mockCondition)));

        // Deploy condition factory
        conditionFactory = new EscrowPeriodConditionFactory();

        // Deploy condition (keyed only by escrowPeriod)
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);

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
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: 0,
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(0),
            salt: 12345
        });
    }

    function _getEnforcedPaymentInfo(MockEscrow.PaymentInfo memory original)
        internal
        view
        returns (MockEscrow.PaymentInfo memory)
    {
        MockEscrow.PaymentInfo memory enforced = original;
        enforced.authorizationExpiry = type(uint48).max;
        enforced.refundExpiry = type(uint48).max;
        enforced.feeReceiver = address(operator);
        enforced.minFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        enforced.maxFeeBps = uint16(MAX_TOTAL_FEE_RATE);
        return enforced;
    }

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

    function _authorize() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        MockEscrow.PaymentInfo memory enforcedInfo = _getEnforcedPaymentInfo(paymentInfo);
        bytes32 paymentInfoHash = escrow.getHash(enforcedInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(enforcedInfo));
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(condition.ESCROW_PERIOD(), ESCROW_PERIOD);
    }

    // ============ Factory Tests ============

    function test_Factory_DeploysCondition() public view {
        address deployedCondition = conditionFactory.getCondition(ESCROW_PERIOD);
        assertEq(deployedCondition, address(condition));
    }

    function test_Factory_IdempotentDeploy() public {
        address first = conditionFactory.deployCondition(ESCROW_PERIOD);
        address second = conditionFactory.deployCondition(ESCROW_PERIOD);
        assertEq(first, second);
    }

    function test_Factory_DifferentPeriodsDifferentConditions() public {
        address cond1 = conditionFactory.deployCondition(ESCROW_PERIOD);
        address cond2 = conditionFactory.deployCondition(ESCROW_PERIOD * 2);
        assertTrue(cond1 != cond2);
    }

    function test_Factory_RevertsOnZeroPeriod() public {
        vm.expectRevert(InvalidEscrowPeriod.selector);
        conditionFactory.deployCondition(0);
    }

    // ============ Register Payment Tests ============

    function test_RegisterPayment_Success() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        uint256 expectedEndTime = block.timestamp + ESCROW_PERIOD;

        vm.expectEmit(true, false, false, true);
        emit PaymentRegistered(paymentInfoHash, expectedEndTime);

        condition.registerPayment(paymentInfo);

        assertEq(condition.getEscrowEndTime(paymentInfo), expectedEndTime);
    }

    function test_RegisterPayment_RevertsIfAlreadyRegistered() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        condition.registerPayment(paymentInfo);

        vm.expectRevert(PaymentAlreadyRegistered.selector);
        condition.registerPayment(paymentInfo);
    }

    // ============ canRelease Tests ============

    function test_CanRelease_FalseBeforeRegistration() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_FalseBeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();
        condition.registerPayment(paymentInfo);

        // Still within escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD - 1);

        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_TrueAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();
        condition.registerPayment(paymentInfo);

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_TrueAfterEscrowPeriodExact() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();
        condition.registerPayment(paymentInfo);

        uint256 endTime = condition.getEscrowEndTime(paymentInfo);

        // Warp to exactly the end time
        vm.warp(endTime);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    // ============ Payer Bypass Tests ============

    function test_PayerBypass_AllowsImmediateRelease() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();
        condition.registerPayment(paymentInfo);

        // Still within escrow period
        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));

        vm.expectEmit(true, true, false, true);
        emit PayerBypassTriggered(paymentInfoHash, payer);

        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
        assertTrue(condition.isPayerBypassed(paymentInfo));
    }

    function test_PayerBypass_WorksWithoutRegistration() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        // Don't register, just bypass
        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_PayerBypass_RevertsIfNotPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        condition.payerBypass(paymentInfo);

        vm.prank(arbiter);
        vm.expectRevert(NotPayer.selector);
        condition.payerBypass(paymentInfo);
    }

    // ============ View Functions Tests ============

    function test_GetEscrowEndTime_ZeroIfNotRegistered() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        assertEq(condition.getEscrowEndTime(paymentInfo), 0);
    }

    function test_IsPayerBypassed_FalseByDefault() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorize();

        assertFalse(condition.isPayerBypassed(paymentInfo));
    }
}
