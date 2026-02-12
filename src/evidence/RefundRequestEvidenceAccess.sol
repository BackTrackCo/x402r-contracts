// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../operator/payment/PaymentOperator.sol";
import {ICondition} from "../plugins/conditions/ICondition.sol";
import {InvalidOperator} from "../types/Errors.sol";
import {NotPayerReceiverOrArbiter} from "./types/Errors.sol";
import {SubmitterRole} from "./types/Types.sol";

/**
 * @title RefundRequestEvidenceAccess
 * @notice Access control modifiers for RefundRequestEvidence contract
 * @dev Payer, receiver, and arbiter (via REFUND_IN_ESCROW_CONDITION) can submit evidence.
 *      Unlike RefundRequestAccess, evidence submission does not distinguish in-escrow vs post-escrow.
 *      If the caller passes the operator's REFUND_IN_ESCROW_CONDITION, they are treated as arbiter
 *      regardless of escrow state (evidence is informational, not financial).
 */
abstract contract RefundRequestEvidenceAccess {
    // ============ Access Control ============

    /**
     * @notice Check if sender is payer, receiver, or arbiter and return their role
     * @param paymentInfo The PaymentInfo struct
     * @return role The SubmitterRole of msg.sender
     */
    function _checkAccessAndGetRole(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        internal
        view
        returns (SubmitterRole role)
    {
        if (msg.sender == paymentInfo.payer) {
            return SubmitterRole.Payer;
        }

        if (msg.sender == paymentInfo.receiver) {
            return SubmitterRole.Receiver;
        }

        // Check arbiter access via operator's REFUND_IN_ESCROW_CONDITION
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        ICondition condition = operator.REFUND_IN_ESCROW_CONDITION();

        // address(0) condition means no arbiter configured — deny
        if (address(condition) == address(0)) {
            revert NotPayerReceiverOrArbiter();
        }

        if (!condition.check(paymentInfo, 0, msg.sender)) {
            revert NotPayerReceiverOrArbiter();
        }

        return SubmitterRole.Arbiter;
    }

    // ============ Operator Validation ============

    /**
     * @notice Modifier to validate operator address is set
     */
    modifier operatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        _checkOperatorNotZero(paymentInfo);
        _;
    }

    function _checkOperatorNotZero(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal pure {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
    }
}
