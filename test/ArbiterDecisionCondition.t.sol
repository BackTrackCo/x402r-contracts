// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbiterDecisionCondition, NotPayerOrArbiter} from "../src/commerce-payments/release-conditions/arbiter-decision/ArbiterDecisionCondition.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {RELEASE} from "../src/commerce-payments/operator/types/Actions.sol";

contract ArbiterDecisionConditionTest is Test {
    ArbiterDecisionCondition public condition;
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

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();

        // Deploy condition (uses payerBypass and arbiterBypass modifiers)
        condition = new ArbiterDecisionCondition();

        // Deploy operator factory
        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );

        // Deploy operator via factory with the arbiter decision condition
        // BEFORE_HOOK = condition (arbiter or payer via bypass modifiers)
        operator = ArbitrationOperator(operatorFactory.deployOperator(
            arbiter,
            address(condition),  // BEFORE_HOOK: arbiter or payer
            address(0)           // AFTER_HOOK: no-op
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

    function _authorizeDirectly() internal returns (bytes32, AuthCaptureEscrow.PaymentInfo memory) {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();

        // Authorize directly through operator
        operator.authorize(
            _toAuthCapturePaymentInfo(paymentInfo),
            PAYMENT_AMOUNT,
            address(0),
            ""
        );

        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        return (paymentInfoHash, _toAuthCapturePaymentInfo(paymentInfo));
    }

    // ============ Release Tests ============

    function test_Release_RevertsIfNotArbiterOrPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Non-arbiter and non-payer cannot release
        vm.prank(receiver);
        vm.expectRevert(NotPayerOrArbiter.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // Random address cannot release
        vm.prank(address(0x1234));
        vm.expectRevert(NotPayerOrArbiter.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_Release_SucceedsForArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Arbiter can release
        vm.prank(arbiter);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Payer Bypass Tests (via payerBypass modifier) ============

    function test_PayerBypass_CanReleaseDirectlyViaOperator() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Non-arbiter cannot release
        vm.prank(receiver);
        vm.expectRevert(NotPayerOrArbiter.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // But payer can bypass via payerBypass modifier
        vm.prank(payer);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_PayerBypass_NonPayerCannotBypass() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        // Non-payer and non-arbiter cannot release
        vm.prank(receiver);
        vm.expectRevert(NotPayerOrArbiter.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        vm.prank(address(0x1234));
        vm.expectRevert(NotPayerOrArbiter.selector);
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    // ============ Direct Hook Tests ============

    function test_Condition_RevertsBased_ForNonPayerOrArbiter() public {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);
        
        // Should revert for non-payer and non-arbiter on RELEASE action
        vm.expectRevert(NotPayerOrArbiter.selector);
        condition.beforeAction(RELEASE, authInfo, PAYMENT_AMOUNT, receiver);
        
        vm.expectRevert(NotPayerOrArbiter.selector);
        condition.beforeAction(RELEASE, authInfo, PAYMENT_AMOUNT, address(0x1234));
    }

    function test_Condition_Succeeds_ForPayer() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);
        
        // Should not revert for payer (any action)
        condition.beforeAction(RELEASE, authInfo, PAYMENT_AMOUNT, payer);
    }

    function test_Condition_Succeeds_ForArbiter() public view {
        MockEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        AuthCaptureEscrow.PaymentInfo memory authInfo = _toAuthCapturePaymentInfo(paymentInfo);
        
        // Should not revert for arbiter (any action)
        condition.beforeAction(RELEASE, authInfo, PAYMENT_AMOUNT, arbiter);
    }
}
