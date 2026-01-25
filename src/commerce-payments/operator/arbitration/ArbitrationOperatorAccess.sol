// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    NotReceiver,
    NotPayer,
    NotArbiter,
    InvalidOperator,
    OnlyOperator
} from "../../types/Errors.sol";

// Forward declaration for reading arbiter
interface IArbitrationOperator {
    function ARBITER() external view returns (address);
}

/**
 * @title ArbitrationOperatorAccess
 * @notice Stateless access control modifiers for payment operations
 * @dev Modifiers read directly from PaymentInfo struct and passed parameters - no state dependencies.
 *      Reusable across ArbitrationOperator, hooks, and release conditions.
 *
 *      Guard Modifiers (AND logic - reverts if not met):
 *      - onlyReceiver, onlyPayer, onlyArbiter: Require specific caller
 *      - validOperator, onlyOperator: Operator validation
 *
 *      Bypass Modifiers (OR logic - skips function body if caller matches):
 *      - payerBypass, receiverBypass, arbiterBypass: Allow specific callers to bypass checks
 */
abstract contract ArbitrationOperatorAccess {

    // ============ Guard Modifiers (AND logic) ============

    /**
     * @notice Modifier to check if sender is the receiver
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver) revert NotReceiver();
        _;
    }

    /**
     * @notice Modifier to check if sender is the payer
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    /**
     * @notice Modifier to check if sender is the arbiter
     * @param arbiter The arbiter address
     */
    modifier onlyArbiter(address arbiter) {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    /**
     * @notice Modifier to validate operator is this contract
     * @param paymentInfo The PaymentInfo struct
     */
    modifier validOperator(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator != address(this)) revert InvalidOperator();
        _;
    }

    /**
     * @notice Modifier to restrict calls to the operator
     * @param operator The operator address from PaymentInfo
     */
    modifier onlyOperator(address operator) {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    // ============ Bypass Modifiers (OR logic) ============

    /**
     * @notice Bypasses the function body if caller is the payer
     * @dev Use for OR logic: if payer, skip all other checks
     * @param paymentInfo The PaymentInfo struct containing payer address
     * @param caller The address attempting the action
     */
    modifier payerBypass(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) {
        if (caller == paymentInfo.payer) return;
        _;
    }

    /**
     * @notice Bypasses the function body if caller is the receiver
     * @dev Use for OR logic: if receiver, skip all other checks
     * @param paymentInfo The PaymentInfo struct containing receiver address
     * @param caller The address attempting the action
     */
    modifier receiverBypass(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) {
        if (caller == paymentInfo.receiver) return;
        _;
    }

    /**
     * @notice Bypasses the function body if caller is the arbiter
     * @dev Use for OR logic: if arbiter, skip all other checks
     * @param paymentInfo The PaymentInfo struct containing operator address
     * @param caller The address attempting the action
     */
    modifier arbiterBypass(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) {
        address arbiter = IArbitrationOperator(paymentInfo.operator).ARBITER();
        if (caller == arbiter) return;
        _;
    }
}
