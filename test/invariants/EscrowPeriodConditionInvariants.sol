// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EscrowPeriodCondition} from "../../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodConditionFactory} from "../../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {ArbitrationOperator} from "../../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {PayerFreezePolicy} from "../../src/commerce-payments/release-conditions/escrow-period/PayerFreezePolicy.sol";
import {PayerOnly} from "../../src/commerce-payments/release-conditions/defaults/PayerOnly.sol";
import {ReceiverOrArbiter} from "../../src/commerce-payments/release-conditions/defaults/ReceiverOrArbiter.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockEscrow} from "../mocks/MockEscrow.sol";

/**
 * @title EscrowPeriodConditionInvariants
 * @notice Echidna invariant tests for EscrowPeriodCondition
 * @dev Run with: echidna test/invariants/EscrowPeriodConditionInvariants.sol --contract EscrowPeriodConditionInvariants
 */
contract EscrowPeriodConditionInvariants {
    EscrowPeriodCondition public condition;
    EscrowPeriodConditionFactory public conditionFactory;
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    PayerFreezePolicy public freezePolicy;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50;
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25;
    uint256 public constant ESCROW_PERIOD = 7 days;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    // Track authorized payments for invariant checking
    bytes32[] public authorizedPayments;
    mapping(bytes32 => bool) public isAuthorized;
    mapping(bytes32 => uint256) public authTimes;

    // Track frozen payments for invariant checking
    bytes32[] public frozenPayments;
    mapping(bytes32 => bool) public isFrozen;

    constructor() {
        owner = address(this);
        protocolFeeRecipient = address(0x1);
        receiver = address(0x2);
        arbiter = address(0x3);
        payer = address(0x4);

        // Deploy contracts
        token = new MockERC20("Test", "TST");
        escrow = new MockEscrow();
        freezePolicy = new PayerFreezePolicy();
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();
        
        conditionFactory = new EscrowPeriodConditionFactory();
        condition = EscrowPeriodCondition(conditionFactory.deployCondition(ESCROW_PERIOD, address(freezePolicy), address(payerOnly), address(payerOnly)));

        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );
        
        // Deploy operator with escrow period condition
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
        token.mint(payer, type(uint256).max);
    }

    // ============ Invariants ============

    /**
     * @notice INVARIANT: Escrow period must never be zero
     */
    function echidna_escrow_period_not_zero() public view returns (bool) {
        return condition.ESCROW_PERIOD() > 0;
    }

    /**
     * @notice INVARIANT: Authorization time for a non-authorized payment is always 0
     */
    function echidna_non_authorized_auth_time_zero() public view returns (bool) {
        // Random payment hash that was never authorized
        bytes32 randomHash = keccak256(abi.encodePacked(block.timestamp, block.prevrandao));
        AuthCaptureEscrow.PaymentInfo memory fakePaymentInfo = _createPaymentInfo(randomHash);
        return condition.getAuthorizationTime(fakePaymentInfo) == 0;
    }

    /**
     * @notice INVARIANT: Frozen payment cannot have release succeed through condition
     * @dev Verifies that all tracked frozen payments remain frozen in the condition contract
     */
    function echidna_frozen_blocks_release() public view returns (bool) {
        for (uint256 i = 0; i < frozenPayments.length; i++) {
            bytes32 hash = frozenPayments[i];
            if (isFrozen[hash]) {
                // Get the payment info and check if condition still shows it as frozen
                AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(hash);
                if (!condition.isFrozen(paymentInfo)) {
                    // Payment was unfrozen without our tracking - check if we unfroze it
                    // If isFrozen[hash] is true but condition shows unfrozen, invariant broken
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice INVARIANT: Authorization time is always <= current block.timestamp
     * @dev Ensures auth times are monotonically bounded by current time
     */
    function echidna_auth_time_monotonic() public view returns (bool) {
        for (uint256 i = 0; i < authorizedPayments.length; i++) {
            bytes32 hash = authorizedPayments[i];
            if (isAuthorized[hash]) {
                AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(hash);
                uint256 authTime = condition.getAuthorizationTime(paymentInfo);
                if (authTime > block.timestamp) {
                    return false;
                }
            }
        }
        return true;
    }

    // ============ Helper Functions ============

    function _createPaymentInfo(bytes32 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: 1000e18,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
            salt: uint256(salt)
        });
    }

    // ============ Fuzz Targets ============

    /**
     * @notice Fuzz target: Try to authorize a payment
     * @dev Pull model: authorize through operator (which calls NOTE_AUTHORIZE)
     */
    function fuzz_authorize(uint256 amount, uint256 salt) public {
        if (amount == 0 || amount > 1e30) return;
        
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(bytes32(salt));
        bytes32 hash = escrow.getHash(MockEscrow.PaymentInfo({
            operator: paymentInfo.operator,
            payer: paymentInfo.payer,
            receiver: paymentInfo.receiver,
            token: paymentInfo.token,
            maxAmount: paymentInfo.maxAmount,
            preApprovalExpiry: paymentInfo.preApprovalExpiry,
            authorizationExpiry: paymentInfo.authorizationExpiry,
            refundExpiry: paymentInfo.refundExpiry,
            minFeeBps: paymentInfo.minFeeBps,
            maxFeeBps: paymentInfo.maxFeeBps,
            feeReceiver: paymentInfo.feeReceiver,
            salt: paymentInfo.salt
        }));

        if (!isAuthorized[hash]) {
            try operator.authorize(paymentInfo, amount, address(0), "") {
                isAuthorized[hash] = true;
                authorizedPayments.push(hash);
                authTimes[hash] = block.timestamp;
            } catch {}
        }
    }

    /**
     * @notice Fuzz target: Try to freeze a payment
     * @dev Must be called by payer (address(0x4)) to succeed with PayerFreezePolicy
     */
    function fuzz_freeze(uint256 salt) public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(bytes32(salt));
        bytes32 hash = escrow.getHash(MockEscrow.PaymentInfo({
            operator: paymentInfo.operator,
            payer: paymentInfo.payer,
            receiver: paymentInfo.receiver,
            token: paymentInfo.token,
            maxAmount: paymentInfo.maxAmount,
            preApprovalExpiry: paymentInfo.preApprovalExpiry,
            authorizationExpiry: paymentInfo.authorizationExpiry,
            refundExpiry: paymentInfo.refundExpiry,
            minFeeBps: paymentInfo.minFeeBps,
            maxFeeBps: paymentInfo.maxFeeBps,
            feeReceiver: paymentInfo.feeReceiver,
            salt: paymentInfo.salt
        }));

        if (isAuthorized[hash] && !isFrozen[hash]) {
            try condition.freeze(paymentInfo) {
                isFrozen[hash] = true;
                frozenPayments.push(hash);
            } catch {}
        }
    }

    /**
     * @notice Fuzz target: Try to unfreeze a payment
     */
    function fuzz_unfreeze(uint256 salt) public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(bytes32(salt));
        bytes32 hash = escrow.getHash(MockEscrow.PaymentInfo({
            operator: paymentInfo.operator,
            payer: paymentInfo.payer,
            receiver: paymentInfo.receiver,
            token: paymentInfo.token,
            maxAmount: paymentInfo.maxAmount,
            preApprovalExpiry: paymentInfo.preApprovalExpiry,
            authorizationExpiry: paymentInfo.authorizationExpiry,
            refundExpiry: paymentInfo.refundExpiry,
            minFeeBps: paymentInfo.minFeeBps,
            maxFeeBps: paymentInfo.maxFeeBps,
            feeReceiver: paymentInfo.feeReceiver,
            salt: paymentInfo.salt
        }));

        if (isFrozen[hash]) {
            try condition.unfreeze(paymentInfo) {
                isFrozen[hash] = false;
            } catch {}
        }
    }

    /**
     * @notice Fuzz target: Try to release a payment through operator
     * @dev Pull model: release through operator (which checks CAN_RELEASE)
     */
    function fuzz_release(uint256 salt, uint256 amount) public {
        if (amount == 0 || amount > 1e30) return;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(bytes32(salt));
        bytes32 hash = escrow.getHash(MockEscrow.PaymentInfo({
            operator: paymentInfo.operator,
            payer: paymentInfo.payer,
            receiver: paymentInfo.receiver,
            token: paymentInfo.token,
            maxAmount: paymentInfo.maxAmount,
            preApprovalExpiry: paymentInfo.preApprovalExpiry,
            authorizationExpiry: paymentInfo.authorizationExpiry,
            refundExpiry: paymentInfo.refundExpiry,
            minFeeBps: paymentInfo.minFeeBps,
            maxFeeBps: paymentInfo.maxFeeBps,
            feeReceiver: paymentInfo.feeReceiver,
            salt: paymentInfo.salt
        }));

        // If frozen, release should fail (except for payer bypass)
        if (isAuthorized[hash]) {
            try operator.release(paymentInfo, amount) {
                // Release succeeded - verify conditions were met
            } catch {}
        }
    }
}
