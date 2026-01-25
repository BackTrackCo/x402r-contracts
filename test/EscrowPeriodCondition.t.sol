// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {EscrowPeriodCondition} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodConditionFactory} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {PayerOnly} from "../src/commerce-payments/release-conditions/defaults/PayerOnly.sol";
import {ReceiverOrArbiter} from "../src/commerce-payments/release-conditions/defaults/ReceiverOrArbiter.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {InvalidEscrowPeriod} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";
import {ConditionNotMet} from "../src/commerce-payments/operator/types/Errors.sol";

contract EscrowPeriodConditionTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;

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
    event PaymentAuthorized(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 authorizationTime);
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
        
        // Deploy default conditions
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();

        // Deploy condition factory and condition first
        conditionFactory = new EscrowPeriodConditionFactory();
        // Pass payerOnly as bypass for both can() and note()
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly)));

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the escrow period condition
        // NOTE_AUTHORIZE = condition (records time)
        // CAN_RELEASE = condition (checks escrow period + payer bypass)
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(0),              // CAN_AUTHORIZE: anyone
            address(condition),      // NOTE_AUTHORIZE: records auth time
            address(condition),      // CAN_RELEASE: checks escrow period
            address(0),              // NOTE_RELEASE: no-op
            address(receiverOrArbiter), // CAN_REFUND_IN_ESCROW
            address(0),              // NOTE_REFUND_IN_ESCROW: no-op
            address(0),              // CAN_REFUND_POST_ESCROW: anyone
            address(0)               // NOTE_REFUND_POST_ESCROW: no-op
        ));

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

        // Authorize through the operator (which calls NOTE_AUTHORIZE = condition)
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo), authTime);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectValues() public view {
        assertEq(condition.ESCROW_PERIOD(), ESCROW_PERIOD);
        assertEq(address(condition.CAN_BYPASS()), address(payerOnly));
        assertEq(address(condition.NOTE_BYPASS()), address(payerOnly));
    }

    // ============ Factory Tests ============

    function test_Factory_DeploysCondition() public view {
        address deployedCondition = conditionFactory.getCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly));
        assertEq(deployedCondition, address(condition));
    }

    function test_Factory_IdempotentDeploy() public {
        address first = conditionFactory.deployCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly));
        address second = conditionFactory.deployCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly));
        assertEq(first, second);
    }

    function test_Factory_DifferentPeriodsDifferentConditions() public {
        address cond1 = conditionFactory.deployCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly));
        address cond2 = conditionFactory.deployCondition(ESCROW_PERIOD * 2, address(0), address(payerOnly), address(payerOnly));
        assertTrue(cond1 != cond2);
    }

    function test_Factory_RevertsOnZeroPeriod() public {
        vm.expectRevert(InvalidEscrowPeriod.selector);
        conditionFactory.deployCondition(0, address(0), address(payerOnly), address(payerOnly));
    }

    function test_ComputeAddressMatchesDeploy() public {
        uint256 period = 20 days;

        // 1. Compute expected address
        address predicted = conditionFactory.computeAddress(period, address(0), address(payerOnly), address(payerOnly));

        // 2. Deploy
        address actual = conditionFactory.deployCondition(period, address(0), address(payerOnly), address(payerOnly));

        // 3. Verify match
        assertEq(predicted, actual, "Computed address should match deployed address");
        assertNotEq(actual, address(0), "Address should not be zero");
        
        // 4. Verify code is laid down
        assertTrue(actual.code.length > 0, "Contract should have code");
    }

    // ============ Authorize Tests ============

    function test_Authorize_TracksAuthorizationTime() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        assertEq(condition.getAuthorizationTime(paymentInfo), authTime);
    }

    function test_Authorize_EmitsEvent() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.expectEmit(false, false, false, true);
        emit PaymentAuthorized(_toAuthCapturePaymentInfo(paymentInfo), block.timestamp);

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
    }

    // ============ Release Tests ============

    function test_Release_RevertsBeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Still within escrow period
        vm.warp(authTime + ESCROW_PERIOD - 1);

        // Non-payer cannot release
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Should succeed (no revert)
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_RevertsIfNotAuthorizedViaOperator() public {
        // Deploy a fresh operator with same condition but don't authorize
        ArbitrationOperator freshOperator = ArbitrationOperator(operatorFactory.deployOperator(
            makeAddr("freshArbiter"),
            address(0),              // CAN_AUTHORIZE: anyone
            address(condition),      // NOTE_AUTHORIZE: records auth time
            address(condition),      // CAN_RELEASE: checks escrow period
            address(0),              // NOTE_RELEASE: no-op
            address(receiverOrArbiter), // CAN_REFUND_IN_ESCROW
            address(0),              // NOTE_REFUND_IN_ESCROW: no-op
            address(0),              // CAN_REFUND_POST_ESCROW: anyone
            address(0)               // NOTE_REFUND_POST_ESCROW: no-op
        ));
        
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        paymentInfo.operator = address(freshOperator);
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Try to release without authorizing through the operator
        vm.expectRevert(ConditionNotMet.selector);
        freshOperator.release(authInfo, PAYMENT_AMOUNT);
    }

    // ============ Payer Bypass Tests (via operator.release) ============

    function test_PayerBypass_CanReleaseDirectlyViaOperator() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Still within escrow period - release by non-payer should fail
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // But payer can bypass (PayerOnly fallback allows it)
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_PayerBypass_NonPayerCannotBypass() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Non-payer cannot release during escrow period
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(arbiter);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ View Functions Tests ============

    function test_GetAuthorizationTime_ZeroIfNotAuthorized() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Not authorized yet
        assertEq(condition.getAuthorizationTime(authInfo), 0);
    }
}

// ============ Freeze Policy Tests ============

import {MockFreezePolicy} from "./mocks/MockFreezePolicy.sol";
import {PayerFreezePolicy} from "../src/commerce-payments/release-conditions/escrow-period/PayerFreezePolicy.sol";
import {
    FundsFrozen,
    EscrowPeriodExpired,
    UnauthorizedFreeze,
    AlreadyFrozen,
    NotFrozen,
    NoFreezePolicy
} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";

contract EscrowPeriodConditionFreezeTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockFreezePolicy public freezePolicy;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;

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
    event PaymentFrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);
    event PaymentUnfrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        freezePolicy = new MockFreezePolicy();
        
        // Deploy default conditions
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();

        // Deploy condition factory and condition WITH freeze policy
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(freezePolicy), address(payerOnly), address(payerOnly)));

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the escrow period condition
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(0),              // CAN_AUTHORIZE: anyone
            address(condition),      // NOTE_AUTHORIZE: records auth time
            address(condition),      // CAN_RELEASE: checks escrow period
            address(0),              // NOTE_RELEASE: no-op
            address(receiverOrArbiter), // CAN_REFUND_IN_ESCROW
            address(0),              // NOTE_REFUND_IN_ESCROW: no-op
            address(0),              // CAN_REFUND_POST_ESCROW: anyone
            address(0)               // NOTE_REFUND_POST_ESCROW: no-op
        ));

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

    function _authorizeViaOperator() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory, uint256) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        uint256 authTime = block.timestamp;

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo), authTime);
    }

    // ============ Freeze Tests ============

    function test_Freeze_BlocksRelease() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Freeze during escrow period
        condition.freeze(paymentInfo);

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Release should fail due to freeze (non-payer)
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Freeze_UnfreezeAllowsRelease() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Freeze then unfreeze during escrow period
        condition.freeze(paymentInfo);
        condition.unfreeze(paymentInfo);

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Release should succeed
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Freeze_PayerCanStillBypass() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Freeze the payment
        condition.freeze(paymentInfo);

        // Release via condition fails (non-payer)
        vm.prank(receiver);
        vm.expectRevert(ConditionNotMet.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // But payer can bypass via PayerOnly fallback
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Freeze_RevertsAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Freezing should fail after escrow period
        vm.expectRevert(EscrowPeriodExpired.selector);
        condition.freeze(paymentInfo);
    }

    function test_Freeze_RevertsIfUnauthorized() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Disable freeze authorization in mock policy
        freezePolicy.setAllowFreeze(false);

        // Freezing should fail
        vm.expectRevert(UnauthorizedFreeze.selector);
        condition.freeze(paymentInfo);
    }

    function test_Freeze_RevertsIfAlreadyFrozen() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Freeze once
        condition.freeze(paymentInfo);

        // Second freeze should fail
        vm.expectRevert(AlreadyFrozen.selector);
        condition.freeze(paymentInfo);
    }

    function test_Unfreeze_RevertsIfNotFrozen() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Unfreeze without freezing should fail
        vm.expectRevert(NotFrozen.selector);
        condition.unfreeze(paymentInfo);
    }

    function test_Unfreeze_RevertsIfUnauthorized() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Freeze first
        condition.freeze(paymentInfo);

        // Disable unfreeze authorization in mock policy
        freezePolicy.setAllowUnfreeze(false);

        // Unfreezing should fail
        vm.expectRevert(UnauthorizedFreeze.selector);
        condition.unfreeze(paymentInfo);
    }

    function test_Unfreeze_AllowedAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaOperator();

        // Freeze during escrow period
        condition.freeze(paymentInfo);

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Unfreeze should still work after escrow period
        condition.unfreeze(paymentInfo);

        // Release should now succeed
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_FreezePolicy_IsSetCorrectly() public view {
        assertEq(address(condition.FREEZE_POLICY()), address(freezePolicy));
    }

    function test_IsFrozen_ReturnsCorrectState() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Not frozen initially
        assertFalse(condition.isFrozen(paymentInfo));

        // Freeze
        condition.freeze(paymentInfo);
        assertTrue(condition.isFrozen(paymentInfo));

        // Unfreeze
        condition.unfreeze(paymentInfo);
        assertFalse(condition.isFrozen(paymentInfo));
    }

    function test_Freeze_EmitsEvent() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        vm.expectEmit(true, true, false, true);
        emit PaymentFrozen(paymentInfo, address(this));

        condition.freeze(paymentInfo);
    }

    function test_Unfreeze_EmitsEvent() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        condition.freeze(paymentInfo);

        vm.expectEmit(true, true, false, true);
        emit PaymentUnfrozen(paymentInfo, address(this));

        condition.unfreeze(paymentInfo);
    }
}

// ============ Payer Freeze Policy Tests ============

contract PayerFreezePolicyTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    PayerFreezePolicy public payerFreezePolicy;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;

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

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        payerFreezePolicy = new PayerFreezePolicy();
        
        // Deploy default conditions
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();

        // Deploy condition factory and condition WITH payer freeze policy
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(payerFreezePolicy), address(payerOnly), address(payerOnly)));

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the escrow period condition
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(0),              // CAN_AUTHORIZE: anyone
            address(condition),      // NOTE_AUTHORIZE: records auth time
            address(condition),      // CAN_RELEASE: checks escrow period
            address(0),              // NOTE_RELEASE: no-op
            address(receiverOrArbiter), // CAN_REFUND_IN_ESCROW
            address(0),              // NOTE_REFUND_IN_ESCROW: no-op
            address(0),              // CAN_REFUND_POST_ESCROW: anyone
            address(0)               // NOTE_REFUND_POST_ESCROW: no-op
        ));

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

    function _authorizeViaOperator() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory, uint256) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        uint256 authTime = block.timestamp;

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo), authTime);
    }

    function test_PayerCanFreeze() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Payer can freeze
        vm.prank(payer);
        condition.freeze(paymentInfo);

        assertTrue(condition.isFrozen(paymentInfo));
    }

    function test_NonPayerCannotFreeze() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Receiver cannot freeze
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        condition.freeze(paymentInfo);

        // Arbiter cannot freeze
        vm.prank(arbiter);
        vm.expectRevert(UnauthorizedFreeze.selector);
        condition.freeze(paymentInfo);
    }

    function test_PayerCanUnfreeze() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Payer freezes
        vm.prank(payer);
        condition.freeze(paymentInfo);

        // Payer can unfreeze
        vm.prank(payer);
        condition.unfreeze(paymentInfo);

        assertFalse(condition.isFrozen(paymentInfo));
    }

    function test_NonPayerCannotUnfreeze() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaOperator();

        // Payer freezes
        vm.prank(payer);
        condition.freeze(paymentInfo);

        // Receiver cannot unfreeze
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedFreeze.selector);
        condition.unfreeze(paymentInfo);
    }
}

// ============ No Freeze Policy Tests ============

contract NoFreezePolicyTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;

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

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        
        // Deploy default conditions
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();

        // Deploy condition WITHOUT freeze policy (address(0))
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(0), address(payerOnly), address(payerOnly)));

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the escrow period condition
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(0),              // CAN_AUTHORIZE: anyone
            address(condition),      // NOTE_AUTHORIZE: records auth time
            address(condition),      // CAN_RELEASE: checks escrow period
            address(0),              // NOTE_RELEASE: no-op
            address(receiverOrArbiter), // CAN_REFUND_IN_ESCROW
            address(0),              // NOTE_REFUND_IN_ESCROW: no-op
            address(0),              // CAN_REFUND_POST_ESCROW: anyone
            address(0)               // NOTE_REFUND_POST_ESCROW: no-op
        ));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);

        vm.prank(payer);
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

    function test_Freeze_RevertsWithNoPolicy() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        vm.expectRevert(NoFreezePolicy.selector);
        condition.freeze(_toAuthCapturePaymentInfo(paymentInfo));
    }

    function test_Unfreeze_RevertsWithNoPolicy() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        vm.expectRevert(NoFreezePolicy.selector);
        condition.unfreeze(_toAuthCapturePaymentInfo(paymentInfo));
    }
}
