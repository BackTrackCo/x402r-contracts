// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EscrowPeriodCondition} from "../src/commerce-payments/conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodRecorder} from "../src/commerce-payments/conditions/escrow-period/EscrowPeriodRecorder.sol";
import {
    EscrowPeriodConditionFactory
} from "../src/commerce-payments/conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {PayerFreezePolicy} from "../src/commerce-payments/conditions/escrow-period/freeze-policy/PayerFreezePolicy.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {ConditionNotMet} from "../src/commerce-payments/operator/types/Errors.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {ICondition} from "../src/commerce-payments/conditions/ICondition.sol";
import {OrCondition} from "../src/commerce-payments/conditions/combinators/OrCondition.sol";
import {PayerCondition} from "../src/commerce-payments/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/commerce-payments/conditions/access/ReceiverCondition.sol";
import {ArbiterCondition} from "../src/commerce-payments/conditions/access/ArbiterCondition.sol";
import {
    InvalidEscrowPeriod,
    EscrowPeriodNotPassed,
    NotAuthorized,
    FundsFrozen,
    EscrowPeriodExpired,
    AlreadyFrozen,
    NotFrozen,
    NoFreezePolicy,
    UnauthorizedFreeze
} from "../src/commerce-payments/conditions/escrow-period/types/Errors.sol";

contract EscrowPeriodConditionTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodRecorder public recorder;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;

    // Conditions
    OrCondition public releaseCondition; // payer OR escrowPeriodCondition
    OrCondition public refundCondition; // receiver OR arbiter

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant ESCROW_PERIOD = 7 days;

    // Events
    event AuthorizationTimeRecorded(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 authorizationTime);
    event EscrowPeriodConditionDeployed(address indexed condition, address indexed recorder, uint256 escrowPeriod);

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();

        // Deploy condition factory and get recorder + condition
        conditionFactory = new EscrowPeriodConditionFactory();
        (address recorderAddr, address conditionAddr) = conditionFactory.deploy(ESCROW_PERIOD, address(0));
        recorder = EscrowPeriodRecorder(recorderAddr);
        condition = EscrowPeriodCondition(conditionAddr);

        // Deploy atomic conditions
        PayerCondition payerCond = new PayerCondition();
        ReceiverCondition receiverCond = new ReceiverCondition();
        ArbiterCondition arbiterCond = new ArbiterCondition();

        // Create release condition: payer OR escrowPeriodCondition
        ICondition[] memory releaseConditions = new ICondition[](2);
        releaseConditions[0] = payerCond;
        releaseConditions[1] = condition;
        releaseCondition = new OrCondition(releaseConditions);

        // Create refund condition: receiver OR arbiter
        ICondition[] memory refundConditions = new ICondition[](2);
        refundConditions[0] = receiverCond;
        refundConditions[1] = arbiterCond;
        refundCondition = new OrCondition(refundConditions);

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        // Deploy operator with escrow period condition
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0), // anyone can authorize
            authorizeRecorder: address(recorder), // records authorization time
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition), // payer OR escrowPeriodPassed
            releaseRecorder: address(0),
            refundInEscrowCondition: address(refundCondition), // receiver OR arbiter
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = ArbitrationOperator(operatorFactory.deployOperator(config));

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

    function _authorizeViaOperator() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory, uint256) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        uint256 authTime = block.timestamp;

        // Authorize through the operator (which calls AUTHORIZE_RECORDER.record())
        operator.authorize(_toAuthCapturePaymentInfo(paymentInfo), PAYMENT_AMOUNT, address(0), "");

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo), authTime);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(recorder.ESCROW_PERIOD(), ESCROW_PERIOD);
        assertEq(address(recorder.FREEZE_POLICY()), address(0));
        assertEq(address(condition.RECORDER()), address(recorder));
    }

    // ============ Factory Tests ============

    function test_Factory_DeploysConditionAndRecorder() public view {
        (address deployedRecorder, address deployedCondition) = conditionFactory.getDeployed(ESCROW_PERIOD, address(0));
        assertEq(deployedRecorder, address(recorder));
        assertEq(deployedCondition, address(condition));
    }

    function test_Factory_IdempotentDeploy() public {
        (address recorder1, address condition1) = conditionFactory.deploy(ESCROW_PERIOD, address(0));
        (address recorder2, address condition2) = conditionFactory.deploy(ESCROW_PERIOD, address(0));
        assertEq(recorder1, recorder2);
        assertEq(condition1, condition2);
    }

    function test_Factory_DifferentPeriods_DifferentAddresses() public {
        (address recorder1,) = conditionFactory.deploy(ESCROW_PERIOD, address(0));
        (address recorder2,) = conditionFactory.deploy(14 days, address(0));
        assertTrue(recorder1 != recorder2);
    }

    // ============ Authorization Recording Tests ============

    function test_Recorder_RecordsAuthorizationTime() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        uint256 authTime = block.timestamp;

        // Authorize through operator
        operator.authorize(authInfo, PAYMENT_AMOUNT, address(0), "");

        // Check recorder stored the auth time
        assertEq(recorder.getAuthorizationTime(authInfo), authTime);
    }

    // ============ Release Condition Tests ============

    function test_Release_RevertsBeforeEscrowPeriodForNonPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Non-payer cannot release before escrow period
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsForPayerBeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Payer can release immediately (via payerBypass in releaseCondition)
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Fast forward past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Anyone can release after escrow period
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsForPayerAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Fast forward past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Payer can also release after escrow period
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Condition Check Tests ============

    function test_Condition_ReturnsFalse_BeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Escrow period check returns false before period passes
        assertFalse(condition.check(paymentInfo, receiver));
    }

    function test_Condition_ReturnsTrue_AfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Fast forward past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Escrow period check returns true after period passes
        assertTrue(condition.check(paymentInfo, receiver));
    }

    function test_Condition_ReturnsFalse_ForUnauthorizedPayment() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Condition returns false for payment that was never authorized
        assertFalse(condition.check(authInfo, receiver));
    }

    // ============ Refund Tests ============

    function test_RefundInEscrow_SucceedsForReceiver() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        vm.prank(receiver);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_RefundInEscrow_SucceedsForArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        vm.prank(arbiter);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }

    function test_RefundInEscrow_RevertsForPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        vm.prank(payer);
        vm.expectRevert(ConditionNotMet.selector);
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));
    }
}

// ============ Freeze Tests (separate contract with freeze policy) ============

contract EscrowPeriodConditionFreezeTest is Test {
    EscrowPeriodRecorder public recorder;
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    PayerFreezePolicy public freezePolicy;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;

    OrCondition public releaseCondition;
    OrCondition public refundCondition;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant ESCROW_PERIOD = 7 days;
    uint256 public constant FREEZE_DURATION = 14 days; // Longer than escrow period so freeze can block release

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();

        // Deploy freeze policy with 3 day freeze duration
        freezePolicy = new PayerFreezePolicy(FREEZE_DURATION);

        // Deploy condition factory with freeze policy
        conditionFactory = new EscrowPeriodConditionFactory();
        (address recorderAddr, address conditionAddr) = conditionFactory.deploy(ESCROW_PERIOD, address(freezePolicy));
        recorder = EscrowPeriodRecorder(recorderAddr);
        condition = EscrowPeriodCondition(conditionAddr);

        // Deploy atomic conditions
        PayerCondition payerCond = new PayerCondition();
        ReceiverCondition receiverCond = new ReceiverCondition();
        ArbiterCondition arbiterCond = new ArbiterCondition();

        // Create release condition: payer OR escrowPeriodCondition
        ICondition[] memory releaseConditions = new ICondition[](2);
        releaseConditions[0] = payerCond;
        releaseConditions[1] = condition;
        releaseCondition = new OrCondition(releaseConditions);

        // Create refund condition: receiver OR arbiter
        ICondition[] memory refundConditions = new ICondition[](2);
        refundConditions[0] = receiverCond;
        refundConditions[1] = arbiterCond;
        refundCondition = new OrCondition(refundConditions);

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        // Deploy operator
        ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
            arbiter: arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(recorder),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(releaseCondition),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(refundCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = ArbitrationOperator(operatorFactory.deployOperator(config));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(receiver, INITIAL_BALANCE);

        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);

        vm.prank(receiver);
        token.approve(address(escrow), type(uint256).max);
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

    function _authorizeViaOperator() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        operator.authorize(authInfo, PAYMENT_AMOUNT, address(0), "");

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, authInfo);
    }

    function test_Freeze_SucceedsForPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Payer can freeze
        vm.prank(payer);
        recorder.freeze(paymentInfo);

        assertTrue(recorder.isFrozen(paymentInfo));
    }

    function test_Freeze_RevertsForNonPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Non-payer cannot freeze
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        recorder.freeze(paymentInfo);
    }

    function test_Freeze_RevertsAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Fast forward past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Cannot freeze after escrow period
        vm.prank(payer);
        vm.expectRevert(EscrowPeriodExpired.selector);
        recorder.freeze(paymentInfo);
    }

    function test_Unfreeze_SucceedsForPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Freeze then unfreeze
        vm.prank(payer);
        recorder.freeze(paymentInfo);

        vm.prank(payer);
        recorder.unfreeze(paymentInfo);

        assertFalse(recorder.isFrozen(paymentInfo));
    }

    function test_FrozenPayment_BlocksRelease() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Freeze the payment
        vm.prank(payer);
        recorder.freeze(paymentInfo);

        // Fast forward past escrow period but WITHIN freeze duration
        // Escrow period is 7 days, freeze duration is 14 days
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Condition should return false because freeze is still active
        assertFalse(condition.check(paymentInfo, receiver));
    }

    function test_FrozenPayment_ExpiresAfterDuration() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Freeze the payment
        vm.prank(payer);
        recorder.freeze(paymentInfo);

        // Fast forward past both escrow period AND freeze duration
        vm.warp(block.timestamp + FREEZE_DURATION + 1);

        // Condition should return true because freeze has expired and escrow period passed
        assertTrue(condition.check(paymentInfo, receiver));
    }

    function test_FrozenPayment_PayerCanStillRelease() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeViaOperator();

        // Freeze the payment
        vm.prank(payer);
        recorder.freeze(paymentInfo);

        // Fast forward past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD + 1);

        // Payer can still release (via PayerCondition in OrCondition)
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }
}
