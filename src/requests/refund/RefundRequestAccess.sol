// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../../operator/payment/PaymentOperator.sol";
import {ICondition} from "../../conditions/ICondition.sol";
import {NotReceiver, NotPayer, NotReceiverOrArbiter, InvalidOperator} from "../../types/Errors.sol";

/**
 * @title RefundRequestAccess
 * @notice Access control modifiers for RefundRequest contract
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
     * @dev Receiver can always approve/deny.
     *      While funds are in escrow, anyone passing the operator's REFUND_IN_ESCROW_CONDITION
     *      can also approve/deny. If the condition is address(0), anyone is allowed.
     *      Post escrow: only receiver.
     *
     *      FRONT-RUNNING RISK: A receiver (or anyone with release condition access) can front-run
     *      an arbiter's updateStatus() call by calling operator.release() to drain capturableAmount
     *      to 0, which locks out the arbiter (post-escrow = receiver only). This is mitigated when
     *      operators use a RELEASE_CONDITION (e.g. EscrowPeriodCondition) that prevents immediate
     *      release. Operators deployed with RELEASE_CONDITION = address(0) are fully exposed to
     *      this race.
     *
     * @param paymentInfo The payment info
     */
    modifier onlyAuthorizedForRefundStatus(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver) {
            PaymentOperator operator = PaymentOperator(paymentInfo.operator);
            AuthCaptureEscrow escrow = operator.ESCROW();
            (, uint120 capturableAmount,) = escrow.paymentState(escrow.getHash(paymentInfo));

            // Post escrow: only receiver
            if (capturableAmount == 0) {
                revert NotReceiverOrArbiter();
            }

            // In escrow: check operator's refund condition (address(0) = allow anyone)
            ICondition condition = operator.REFUND_IN_ESCROW_CONDITION();
            if (address(condition) != address(0) && !condition.check(paymentInfo, 0, msg.sender)) {
                revert NotReceiverOrArbiter();
            }
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
