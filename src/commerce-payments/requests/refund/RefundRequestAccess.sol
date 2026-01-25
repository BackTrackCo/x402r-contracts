// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {
    NotReceiver,
    NotReceiverOrArbiter,
    InvalidOperator
} from "../../types/Errors.sol";

/**
 * @title RefundRequestAccess
 * @notice Stateless access control for RefundRequest - complements ArbitrationOperatorAccess
 * @dev Contains RefundRequest-specific modifiers. Use with ArbitrationOperatorAccess for onlyPayer.
 */
abstract contract RefundRequestAccess {

    // ============ Refund Status Authorization ============

    /**
     * @notice Modifier to check authorization for updating refund status
     * @dev In escrow: receiver OR arbiter can update
     *      Post escrow: only receiver can update
     */
    modifier onlyAuthorizedForRefundStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        (, uint120 capturableAmount,) = operator.ESCROW().paymentState(operator.ESCROW().getHash(paymentInfo));

        if (capturableAmount > 0) {
            if (msg.sender != paymentInfo.receiver && msg.sender != operator.ARBITER()) {
                revert NotReceiverOrArbiter();
            }
        } else {
            if (msg.sender != paymentInfo.receiver) {
                revert NotReceiver();
            }
        }
        _;
    }

    // ============ Operator Validation ============

    /**
     * @notice Modifier to validate operator address is set
     * @dev Different from ArbitrationOperatorAccess.validOperator which checks operator == address(this)
     */
    modifier operatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
        _;
    }

}
