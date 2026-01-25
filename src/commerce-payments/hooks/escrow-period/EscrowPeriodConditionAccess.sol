// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {HookAccess} from "../types/HookAccess.sol";
import {IFreezePolicy} from "./types/IFreezePolicy.sol";
import {NoFreezePolicy, UnauthorizedFreeze} from "./types/Errors.sol";

/**
 * @title EscrowPeriodConditionAccess
 * @notice Stateless access control modifiers for escrow period operations
 * @dev Extends HookAccess for common hook modifiers (onlyOperator, payerBypass, etc.)
 *      Adds freeze policy-specific modifiers.
 *      Reusable across EscrowPeriodCondition and related contracts.
 */
abstract contract EscrowPeriodConditionAccess is HookAccess {

    // ============ Freeze Policy Modifiers ============

    /// @notice Modifier to require freeze policy is set
    /// @param freezePolicy The freeze policy to check
    modifier requireFreezePolicy(IFreezePolicy freezePolicy) {
        if (address(freezePolicy) == address(0)) revert NoFreezePolicy();
        _;
    }

    /// @notice Modifier to check caller is authorized to freeze via policy
    /// @param freezePolicy The freeze policy contract
    /// @param paymentInfo The payment to freeze
    modifier authorizedToFreeze(IFreezePolicy freezePolicy, AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (!freezePolicy.canFreeze(paymentInfo, msg.sender)) revert UnauthorizedFreeze();
        _;
    }

    /// @notice Modifier to check caller is authorized to unfreeze via policy
    /// @param freezePolicy The freeze policy contract
    /// @param paymentInfo The payment to unfreeze
    modifier authorizedToUnfreeze(IFreezePolicy freezePolicy, AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (!freezePolicy.canUnfreeze(paymentInfo, msg.sender)) revert UnauthorizedFreeze();
        _;
    }
}
