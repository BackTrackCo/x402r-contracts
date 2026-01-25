// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title INoteCondition
 * @notice Generic interface for recording/noting that an action occurred
 * @dev Used for NOTE_AUTHORIZE, NOTE_RELEASE, NOTE_REFUND_IN_ESCROW, NOTE_REFUND_POST_ESCROW slots.
 *      The slot determines the action, not the condition implementation.
 *      SECURITY: Implementations must validate msg.sender == paymentInfo.operator.
 */
interface INoteCondition {
    /**
     * @notice Record that an action occurred
     * @dev Must validate msg.sender == paymentInfo.operator
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount involved in the action
     * @param caller The address that performed the action
     */
    function note(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external;
}
