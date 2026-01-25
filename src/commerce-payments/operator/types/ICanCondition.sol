// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title ICanCondition
 * @notice Generic interface for checking if an action is allowed
 * @dev Used for CAN_AUTHORIZE, CAN_RELEASE, CAN_REFUND_IN_ESCROW, CAN_REFUND_POST_ESCROW slots.
 *      The slot determines the action, not the condition implementation.
 *      Conditions can read arbiter via ArbitrationOperator(paymentInfo.operator).ARBITER().
 */
interface ICanCondition {
    /**
     * @notice Check if the action is allowed
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount involved in the action
     * @param caller The address attempting the action
     * @return True if the action is allowed
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view returns (bool);
}
