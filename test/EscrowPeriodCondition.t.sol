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
import {InvalidEscrowPeriod} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";
import {ReleaseLocked} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";
import {UnauthorizedCaller} from "../src/commerce-payments/operator/types/Errors.sol";

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

    function test_ComputeAddressMatchesDeploy() public {
        uint256 period = 20 days;
        
        // 1. Compute expected address
        address predicted = conditionFactory.computeAddress(period);

        // 2. Deploy
        address actual = conditionFactory.deployCondition(period);

        // 3. Verify match
        assertEq(predicted, actual, "Computed address should match deployed address");
        assertNotEq(actual, address(0), "Address should not be zero");
        
        // 4. Verify code is laid down
        assertTrue(actual.code.length > 0, "Contract should have code");
    }

    // ============ Authorize Tests ============

    function test_Authorize_TracksAuthorizationTime() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        assertEq(condition.getAuthorizationTime(paymentInfo), authTime);
    }

    function test_Authorize_EmitsEvent() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.expectEmit(false, false, false, true);
        emit PaymentAuthorized(_toAuthCapturePaymentInfo(paymentInfo), block.timestamp);

        condition.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
    }

    // ============ Release Tests ============

    function test_AuthorizeDirectly_Reverts() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        vm.expectRevert(UnauthorizedCaller.selector);
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );
    }

    function test_Release_RevertsBeforeEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Still within escrow period
        vm.warp(authTime + ESCROW_PERIOD - 1);

        vm.expectRevert(ReleaseLocked.selector);
        condition.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsAfterEscrowPeriod() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Should succeed (no revert)
        condition.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_RevertsIfNotAuthorizedViaCondition() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);

        // Try to release without authorizing through the condition
        vm.expectRevert(ReleaseLocked.selector);
        condition.release(authInfo, PAYMENT_AMOUNT);
    }

    // ============ Payer Bypass Tests (via operator.release) ============

    function test_PayerBypass_CanReleaseDirectlyViaOperator() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        // Still within escrow period - release via condition should fail
        vm.expectRevert(ReleaseLocked.selector);
        condition.release(paymentInfo, PAYMENT_AMOUNT);

        // But payer can bypass by calling operator.release() directly
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_PayerBypass_NonPayerCannotBypass() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        // Non-payer cannot call operator.release() directly
        vm.prank(receiver);
        vm.expectRevert(UnauthorizedCaller.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(arbiter);
        vm.expectRevert(UnauthorizedCaller.selector);
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

// ============ Freeze Checker Tests ============

import {MockFreezeChecker} from "./mocks/MockFreezeChecker.sol";
import {FundsFrozen} from "../src/commerce-payments/release-conditions/escrow-period/types/Errors.sol";

contract EscrowPeriodConditionFreezeTest is Test {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockFreezeChecker public freezeChecker;

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
        freezeChecker = new MockFreezeChecker();

        // Deploy condition factory and condition WITH freeze checker
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(freezeChecker)));

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

        condition.authorize(
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
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Freeze the payment
        freezeChecker.freeze(paymentInfoHash);

        // Release should fail due to freeze
        vm.expectRevert(FundsFrozen.selector);
        condition.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Freeze_UnfreezeAllowsRelease() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 authTime) = _authorizeViaCondition();

        // Warp past escrow period
        vm.warp(authTime + ESCROW_PERIOD);

        // Freeze then unfreeze
        freezeChecker.freeze(paymentInfoHash);
        freezeChecker.unfreeze(paymentInfoHash);

        // Release should succeed
        condition.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Freeze_PayerCanStillBypass() public {
        (bytes32 paymentInfoHash, AuthCaptureEscrow.PaymentInfo memory paymentInfo,) = _authorizeViaCondition();

        // Freeze the payment
        freezeChecker.freeze(paymentInfoHash);

        // Release via condition fails
        vm.expectRevert(FundsFrozen.selector);
        condition.release(paymentInfo, PAYMENT_AMOUNT);

        // But payer can bypass by calling operator directly
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_FreezeChecker_IsSetCorrectly() public view {
        assertEq(address(condition.FREEZE_CHECKER()), address(freezeChecker));
    }
}

