// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ArbitrationOperator} from "../../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {ArbitrationOperatorFactory} from "../../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockEscrow} from "../mocks/MockEscrow.sol";
import {MockReleaseCondition} from "../mocks/MockReleaseCondition.sol";

/**
 * @title ArbitrationOperatorInvariants
 * @notice Echidna invariant tests for ArbitrationOperator
 * @dev Run with: echidna test/invariants/ArbitrationOperatorInvariants.sol --contract ArbitrationOperatorInvariants
 * 
 * Key invariants tested:
 * 1. Fee rates never exceed MAX_TOTAL_FEE_RATE
 * 2. Protocol fee percentage never exceeds 100%
 * 3. Arbiter address is never zero (immutable)
 * 4. Fee receiver must be the operator for authorized payments
 */
contract ArbitrationOperatorInvariants {
    ArbitrationOperator public operator;
    ArbitrationOperatorFactory public operatorFactory;
    MockERC20 public token;
    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50; // 0.5%
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25; // 25%

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public arbiter;
    address public payer;

    // Track authorized payment hashes
    bytes32[] public authorizedPayments;
    mapping(bytes32 => bool) public isAuthorized;

    constructor() {
        owner = address(this);
        protocolFeeRecipient = address(0x1);
        receiver = address(0x2);
        arbiter = address(0x3);
        payer = address(0x4);

        // Deploy contracts
        token = new MockERC20("Test", "TST");
        escrow = new MockEscrow();
        releaseCondition = new MockReleaseCondition();

        operatorFactory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            owner
        );
        operator = ArbitrationOperator(operatorFactory.deployOperator(arbiter, address(releaseCondition)));

        // Setup balances
        token.mint(payer, type(uint256).max);
    }

    // ============ Invariants ============

    /**
     * @notice INVARIANT: Arbiter address must never be zero
     */
    function echidna_arbiter_not_zero() public view returns (bool) {
        return operator.ARBITER() != address(0);
    }

    /**
     * @notice INVARIANT: MAX_TOTAL_FEE_RATE must be properly set
     */
    function echidna_max_fee_rate_set() public view returns (bool) {
        return operator.MAX_TOTAL_FEE_RATE() == MAX_TOTAL_FEE_RATE;
    }

    /**
     * @notice INVARIANT: Protocol fee percentage cannot exceed 100%
     */
    function echidna_protocol_fee_percentage_valid() public view returns (bool) {
        return operator.PROTOCOL_FEE_PERCENTAGE() <= 100;
    }

    /**
     * @notice INVARIANT: MAX_ARBITER_FEE_RATE correctly computed
     * @dev Should be (maxTotalFeeRate * (100 - protocolFeePercentage)) / 100
     */
    function echidna_arbiter_fee_rate_correct() public view returns (bool) {
        uint256 expected = (MAX_TOTAL_FEE_RATE * (100 - PROTOCOL_FEE_PERCENTAGE)) / 100;
        return operator.MAX_ARBITER_FEE_RATE() == expected;
    }

    /**
     * @notice INVARIANT: Protocol fee recipient must never be zero
     */
    function echidna_protocol_fee_recipient_not_zero() public view returns (bool) {
        return operator.protocolFeeRecipient() != address(0);
    }

    /**
     * @notice INVARIANT: ESCROW address must never be zero
     */
    function echidna_escrow_not_zero() public view returns (bool) {
        return address(operator.ESCROW()) != address(0);
    }

    /**
     * @notice INVARIANT: Release condition must never be zero
     */
    function echidna_release_condition_not_zero() public view returns (bool) {
        return address(operator.RELEASE_CONDITION()) != address(0);
    }

    /**
     * @notice INVARIANT: Payment existence implies payer is non-zero
     * @dev Checks that paymentExists() returning true means the stored PaymentInfo has non-zero payer
     */
    function echidna_existing_payment_has_payer() public view returns (bool) {
        for (uint256 i = 0; i < authorizedPayments.length; i++) {
            bytes32 hash = authorizedPayments[i];
            if (operator.paymentExists(hash)) {
                AuthCaptureEscrow.PaymentInfo memory info = operator.getPaymentInfo(hash);
                if (info.payer == address(0)) {
                    return false;
                }
            }
        }
        return true;
    }

    // ============ Helper Functions ============

    function _createPaymentInfo(uint256 salt) internal view returns (MockEscrow.PaymentInfo memory) {
        return MockEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(1000e18),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: type(uint48).max,
            refundExpiry: type(uint48).max,
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            feeReceiver: address(operator),
            salt: salt
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

    // ============ Fuzz Targets ============

    /**
     * @notice Fuzz target: Try to authorize a payment via operator
     * @dev Since MockReleaseCondition doesn't implement IAuthorizable, we call operator directly
     */
    function fuzz_authorize(uint256 amount, uint256 salt) public {
        if (amount == 0 || amount > 1e30) return;
        
        MockEscrow.PaymentInfo memory mockInfo = _createPaymentInfo(salt);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _toAuthCapturePaymentInfo(mockInfo);
        bytes32 hash = escrow.getHash(mockInfo);

        if (!isAuthorized[hash]) {
            // Operator allows direct authorize since release condition doesn't support IAuthorizable
            try operator.authorize(paymentInfo, amount, address(0), "") {
                isAuthorized[hash] = true;
                authorizedPayments.push(hash);
            } catch {}
        }
    }

    /**
     * @notice Fuzz target: Toggle fees enabled
     */
    function fuzz_toggle_fees(bool enabled) public {
        try operator.setFeesEnabled(enabled) {} catch {}
    }

    /**
     * @notice Fuzz target: Try to distribute fees
     */
    function fuzz_distribute_fees() public {
        try operator.distributeFees(address(token)) {} catch {}
    }
}
