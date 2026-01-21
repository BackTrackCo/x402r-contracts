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
import {
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
    event PaymentAuthorized(bytes32 indexed paymentInfoHash, uint256 authorizationTime);
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

        // Deploy condition factory and condition first
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD));

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the escrow period condition
        operator = ArbitrationOperator(operatorFactory.deployOperator(arbiter, address(condition)));

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
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
            salt: 12345
        });
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

    function _authorizeViaCondition() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory, uint256) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        uint256 authTime = block.timestamp;

        // Authorize through the condition contract
        condition.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo), authTime);
    }

    function _authorizeDirectly() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        // Authorize directly through the operator (bypassing condition)
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo));
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

    // ============ Authorize Tests ============

    function test_Authorize_TracksAuthorizationTime() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        assertEq(condition.getAuthorizationTime(paymentInfo), authTime);
    }

    function test_Authorize_EmitsEvent() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        bytes32 expectedHash = escrow.getHash(paymentInfo);

        vm.expectEmit(true, false, false, true);
        emit PaymentAuthorized(expectedHash, block.timestamp);

        condition.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
    }

    // ============ canRelease Tests ============

    function test_CanRelease_FalseIfNotAuthorizedViaCondition() public {
        // Authorize directly through operator (not through condition)
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Should return false because authorizationTimes[hash] == 0
        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_FalseBeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Still within escrow period
        vm.warp(authTime + ESCROW_PERIOD - 1);

        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_TrueAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_TrueAfterEscrowPeriodExact() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Warp to exactly the end time
        vm.warp(authTime + ESCROW_PERIOD);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    // ============ Payer Bypass Tests ============

    function test_PayerBypass_AllowsImmediateRelease() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        // Still within escrow period
        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));

        vm.expectEmit(true, true, false, true);
        emit PayerBypassTriggered(paymentInfoHash, payer);

        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
        assertTrue(condition.isPayerBypassed(paymentInfo));
    }

    function test_PayerBypass_WorksEvenIfNotAuthorizedViaCondition() public {
        // Authorize directly through operator
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Bypass should still work
        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        // Now canRelease should return true
        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_PayerBypass_RevertsIfNotPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        condition.payerBypass(paymentInfo);

        vm.prank(arbiter);
        vm.expectRevert(NotPayer.selector);
        condition.payerBypass(paymentInfo);
    }

    // ============ View Functions Tests ============

    function test_GetAuthorizationTime_ZeroIfNotAuthorizedViaCondition() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        assertEq(condition.getAuthorizationTime(paymentInfo), 0);
    }

    function test_IsPayerBypassed_FalseByDefault() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        assertFalse(condition.isPayerBypassed(paymentInfo));
    }
}
