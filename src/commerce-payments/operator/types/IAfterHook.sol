// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IAfterHook
 * @notice Generic interface for notifications after any action
 * @dev SECURITY: Implementations must validate msg.sender == paymentInfo.operator.
 *      Action parameter indicates which action occurred:
 *      - AUTHORIZE, RELEASE, REFUND_IN_ESCROW, REFUND_POST_ESCROW
 *      Import Actions.sol for action constants.
 */
interface IAfterHook {
    /**
     * @notice Called after an action occurs
     * @dev Must validate msg.sender == paymentInfo.operator
     * @param action The action that occurred (AUTHORIZE, RELEASE, etc.)
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount involved in the action
     * @param caller The address that performed the action
     */
    function afterAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external;
}
