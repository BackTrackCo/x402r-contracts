// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ArbiterDecisionCondition} from "../src/commerce-payments/release-conditions/arbiter-decision/ArbiterDecisionCondition.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {NotArbiter} from "../src/commerce-payments/release-conditions/arbiter-decision/types/Errors.sol";
import {NotPayer} from "../src/commerce-payments/release-conditions/shared/types/Errors.sol";

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

    // Events
    event ArbiterApproved(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed arbiter);
    event PayerBypassTriggered(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer);

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");

        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();

        // Deploy condition (singleton)
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

    // ============ canRelease Tests ============

    function test_CanRelease_FalseInitially() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_CanRelease_TrueAfterArbiterApprove() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        vm.prank(arbiter);
        condition.arbiterApprove(paymentInfo);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_ArbiterApprove_RevertsIfNotArbiter() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        vm.prank(payer);
        vm.expectRevert(NotArbiter.selector);
        condition.arbiterApprove(paymentInfo);

        vm.prank(receiver);
        vm.expectRevert(NotArbiter.selector);
        condition.arbiterApprove(paymentInfo);
    }

    // ============ Payer Bypass Tests ============

    function test_PayerBypass_AllowsRelease() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        assertFalse(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));

        vm.expectEmit(true, false, false, true);
        emit PayerBypassTriggered(paymentInfo, payer);

        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
        assertTrue(condition.isPayerBypassed(paymentInfo));
    }

    function test_PayerBypass_WorksWithoutArbiterApproval() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        vm.prank(payer);
        condition.payerBypass(paymentInfo);

        // Even though arbiter hasn't approved
        assertFalse(condition.isApproved(escrow.getHash(_createPaymentInfo()))); // Check directly
        // Wait, Need hash
        
        assertTrue(condition.canRelease(paymentInfo, PAYMENT_AMOUNT));
    }

    function test_PayerBypass_RevertsIfNotPayer() public {
        (, AuthCaptureEscrow.PaymentInfo memory paymentInfo) = _authorizeDirectly();

        vm.prank(receiver);
        vm.expectRevert(NotPayer.selector);
        condition.payerBypass(paymentInfo);
    }
}
