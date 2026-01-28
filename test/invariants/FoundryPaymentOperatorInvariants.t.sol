// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../../src/plugins/fees/StaticFeeCalculator.sol";
import {PaymentOperatorHandler} from "./handlers/PaymentOperatorHandler.sol";

/**
 * @title FoundryPaymentOperatorInvariants
 * @notice Handler-based Foundry invariant tests for PaymentOperator.
 *         Uses PaymentOperatorHandler to drive state transitions and asserts global invariants.
 */
contract FoundryPaymentOperatorInvariants is Test {
    PaymentOperator public operator;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    ProtocolFeeConfig public protocolFeeConfig;
    PaymentOperatorHandler public handler;

    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PROTOCOL_BPS = 25;
    uint256 public constant OPERATOR_BPS = 50;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy with fees for meaningful invariant checks
        StaticFeeCalculator protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);
        StaticFeeCalculator opCalc = new StaticFeeCalculator(OPERATOR_BPS);

        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: operatorFeeRecipient,
            feeCalculator: address(opCalc),
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
        operator = PaymentOperator(factory.deployOperator(config));

        // Fund payer
        token.mint(payer, type(uint128).max);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);

        // Deploy handler
        handler = new PaymentOperatorHandler(operator, escrow, collector, token, payer, receiver);

        // Target only the handler
        targetContract(address(handler));
    }

    // ============ Invariants ============

    /// @notice Accumulated protocol fees must never exceed operator token balance
    function invariant_accumulatedProtocolFeesLteBalance() public view {
        uint256 accumulated = operator.accumulatedProtocolFees(address(token));
        uint256 balance = token.balanceOf(address(operator));
        assertLe(accumulated, balance, "Accumulated protocol fees must not exceed operator balance");
    }

    /// @notice For every tracked payment, captured + refunded <= authorized
    function invariant_noDoubleSpend() public view {
        uint256 count = handler.ghost_paymentHashCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 hash = handler.ghost_paymentHashes(i);
            uint256 authorized = handler.ghost_authorizedAmounts(hash);
            uint256 captured = handler.ghost_capturedAmounts(hash);
            uint256 refunded = handler.ghost_refundedAmounts(hash);
            assertLe(captured + refunded, authorized, "Captured + refunded must not exceed authorized");
        }
    }

    /// @notice Escrow token store balance >= sum of all capturable + refundable amounts
    function invariant_solvency() public view {
        address tokenStore = escrow.getTokenStore(address(operator));
        uint256 actualBalance = token.balanceOf(tokenStore);

        uint256 totalObligations = 0;
        uint256 count = handler.ghost_paymentHashCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 hash = handler.ghost_paymentHashes(i);
            (, uint120 capturable, uint120 refundable) = escrow.paymentState(hash);
            totalObligations += capturable + refundable;
        }

        assertGe(actualBalance, totalObligations, "Escrow balance must cover all obligations");
    }

    /// @notice Fee distribution conservation: after distribution, protocol + operator recipients got all fees
    function invariant_feeDistributionConservation() public view {
        // Total fees in the system = operator balance + already distributed to recipients
        uint256 opBalance = token.balanceOf(address(operator));
        uint256 protocolRecipientBalance = token.balanceOf(protocolFeeRecipient);
        uint256 operatorRecipientBalance = token.balanceOf(operatorFeeRecipient);

        // These balances should account for all fees ever collected
        // (operator balance holds undistributed, recipients hold distributed)
        uint256 totalFees = opBalance + protocolRecipientBalance + operatorRecipientBalance;

        // Total fees should be consistent with released amounts
        uint256 totalReleased = handler.ghost_totalReleased();
        uint256 expectedMaxFees = (totalReleased * (PROTOCOL_BPS + OPERATOR_BPS)) / 10000;

        // Allow for rounding: total fees <= expected max + rounding tolerance
        assertLe(
            totalFees, expectedMaxFees + handler.ghost_callCount_release(), "Fees must not exceed expected maximum"
        );
    }
}
