// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IBeforeHook
 * @notice Generic interface for permission checks before any action (revert-based)
 * @dev Reverts if action is not allowed. No revert = allowed.
 *      Action parameter indicates which action is being performed:
 *      - AUTHORIZE, RELEASE, REFUND_IN_ESCROW, REFUND_POST_ESCROW
 *      Import Actions.sol for action constants.
 */
interface IBeforeHook {
    /**
     * @notice Check if the action is allowed. Reverts if not.
     * @param action The action being performed (AUTHORIZE, RELEASE, etc.)
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount involved in the action
     * @param caller The address attempting the action
     */
    function beforeAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view;
}
