// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {OnlyOperator, NotPayer} from "../../types/Errors.sol";

// Forward declaration for reading arbiter
interface IArbitrationOperator {
    function ARBITER() external view returns (address);
}

/**
 * @title HookAccess
 * @notice Stateless access control modifiers for hook contracts
 * @dev Modifiers for IBeforeHook and IAfterHook implementations.
 *
 *      Guard Modifiers (AND logic - reverts if not met):
 *      - onlyOperator: Ensures caller is the operator (for afterAction hooks)
 *
 *      Bypass Modifiers (OR logic - skips function body if caller matches):
 *      - payerBypass, receiverBypass, arbiterBypass: Allow specific callers to bypass checks
 */
abstract contract HookAccess {

    // ============ Guard Modifiers (AND logic) ============

    /**
     * @notice Modifier to restrict calls to the operator
     * @dev Used by afterAction hooks to ensure only operator can call
     * @param operator The operator address from paymentInfo.operator
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
