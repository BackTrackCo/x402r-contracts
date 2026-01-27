// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {NotReceiver, NotPayer, InvalidOperator} from "../../types/Errors.sol";

/**
 * @title RefundRequestAccess
 * @notice Stateless access control for RefundRequest contract
 * @dev Contains ALL modifiers used by RefundRequest.
 *      Separated from PaymentOperatorAccess for proper code reuse.
 */
abstract contract RefundRequestAccess {
    // ============ Role-Based Access Control ============

    /**
     * @notice Modifier to check if sender is the payer
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    /**
     * @notice Modifier to check if sender is the receiver
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver) revert NotReceiver();
        _;
    }

    // ============ Refund Status Authorization ============

    /**
     * @notice Modifier to check authorization for updating refund status
     * @dev In escrow: receiver can update (operator conditions handle additional authorization)
     *      Post escrow: only receiver can update
     * @param paymentInfo The payment info
     */
    modifier onlyAuthorizedForRefundStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        // Get escrow state to determine if in escrow or post-escrow
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        AuthCaptureEscrow escrow = operator.ESCROW();
        (, uint120 capturableAmount,) = escrow.paymentState(escrow.getHash(paymentInfo));

        // In escrow: receiver can update (operator's conditions will handle additional auth like arbiter)
        // Post escrow: only receiver can update
        if (msg.sender != paymentInfo.receiver) {
            // If not receiver, check if in escrow and allow (operator conditions will validate)
            if (capturableAmount == 0) {
                // Post-escrow: only receiver allowed
                revert NotReceiver();
            }
            // In escrow: allow non-receiver (operator's refund conditions will validate authorization)
            // This enables flexible authorization via conditions (e.g., StaticAddressCondition)
        }
        _;
    }

    // ============ Operator Validation ============

    /**
     * @notice Modifier to validate operator address is set
     * @dev Different from PaymentOperatorAccess.validOperator which checks operator == address(this)
     */
    modifier operatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
        _;
    }
}
