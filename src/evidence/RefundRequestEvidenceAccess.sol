// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {RefundRequest} from "../requests/refund/RefundRequest.sol";
import {InvalidOperator} from "../types/Errors.sol";
import {NotPayerReceiverOrArbiter} from "./types/Errors.sol";
import {SubmitterRole} from "./types/Types.sol";

/**
 * @title RefundRequestEvidenceAccess
 * @notice Access control modifiers for RefundRequestEvidence contract
 * @dev Payer, receiver, and arbiter can submit evidence.
 *      Arbiter identity is read from REFUND_REQUEST.ARBITER().
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

        // Check arbiter access via RefundRequest's immutable ARBITER
        if (msg.sender == _getRefundRequest().ARBITER()) {
            return SubmitterRole.Arbiter;
        }

        revert NotPayerReceiverOrArbiter();
    }

    /// @dev Subclass must provide the RefundRequest reference
    function _getRefundRequest() internal view virtual returns (RefundRequest);

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
