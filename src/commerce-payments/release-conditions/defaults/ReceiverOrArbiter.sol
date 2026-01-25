// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ICanCondition} from "../../operator/types/ICanCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Forward declaration for reading arbiter
interface IArbitrationOperator {
    function ARBITER() external view returns (address);
}

/**
 * @title ReceiverOrArbiter
 * @notice Default condition that allows either the receiver or arbiter to perform an action
 * @dev Singleton - deploy once and reuse across all operators.
 *      Commonly used for CAN_REFUND_IN_ESCROW to allow receiver or arbiter to refund.
 *      Reads arbiter from the operator via paymentInfo.operator.
 */
contract ReceiverOrArbiter is ICanCondition {
    /**
     * @notice Check if the caller is the receiver or arbiter
     * @param paymentInfo The PaymentInfo struct
     * @param caller The address attempting the action
     * @return True if caller is receiver or arbiter
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256, /* amount */
        address caller
    ) external view returns (bool) {
        if (caller == paymentInfo.receiver) return true;
        address arbiter = IArbitrationOperator(paymentInfo.operator).ARBITER();
        return caller == arbiter;
    }
}
