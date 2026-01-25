// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IBeforeHook} from "../types/IBeforeHook.sol";
import {HookAccess} from "../types/HookAccess.sol";
import {RELEASE} from "../types/Actions.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Caller is not authorized (not payer or arbiter)
error NotPayerOrArbiter();

/**
 * @title ArbiterDecisionCondition
 * @notice Release condition where payer or arbiter can release funds.
 *         Implements IBeforeHook with action routing.
 *         Uses payerBypass and arbiterBypass modifiers for clean OR logic.
 *
 * @dev Pull Model Architecture:
 *      - Only guards RELEASE action
 *      - Payer bypass via payerBypass modifier
 *      - Arbiter bypass via arbiterBypass modifier
 *      - If neither, reverts with NotPayerOrArbiter
 *      - Other actions: allow through
 *
 *      Operator Configuration:
 *      BEFORE_HOOK = arbiterDecisionCondition
 */
contract ArbiterDecisionCondition is IBeforeHook, HookAccess {
    /**
     * @notice Check if action is allowed. Reverts if not.
     * @dev Routes based on action parameter. Only RELEASE is guarded.
     * @param action The action being performed
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount (unused)
     * @param caller The address attempting the action
     */
    function beforeAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view override {
        if (action == RELEASE) {
            _beforeRelease(paymentInfo, caller);
        }
        // Other actions: allow through (no revert)

        // Silence unused variable warning
        (amount);
    }

    /**
     * @notice Internal release check with payer and arbiter bypass
     * @dev Payer or arbiter can release. If neither, reverts.
     * @param paymentInfo PaymentInfo struct
     * @param caller The address attempting the release
     */
    function _beforeRelease(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    )
        internal
        view
        payerBypass(paymentInfo, caller)
        arbiterBypass(paymentInfo, caller)
    {
        // If we reach here, caller is neither payer nor arbiter
        revert NotPayerOrArbiter();
    }
}
