// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IBeforeHook} from "../../operator/types/IBeforeHook.sol";
import {ArbitrationOperatorAccess} from "../../operator/arbitration/ArbitrationOperatorAccess.sol";
import {RELEASE} from "../../operator/types/Actions.sol";
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
contract ArbiterDecisionCondition is IBeforeHook, ArbitrationOperatorAccess {
    /**
     * @notice Check if action is allowed. Reverts if not.
     * @dev Only guards RELEASE. Payer and arbiter bypass via modifiers.
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
    )
        external
        view
        override
        payerBypass(paymentInfo, caller)
        arbiterBypass(paymentInfo, caller)
    {
        if (action == RELEASE) {
            // If we reach here for RELEASE, caller is neither payer nor arbiter
            revert NotPayerOrArbiter();
        }
        // Other actions: allow through (no revert)

        // Silence unused variable warning
        (amount);
    }
}
