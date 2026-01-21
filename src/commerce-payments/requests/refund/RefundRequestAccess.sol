// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {
    NotReceiver,
    NotPayer,
    NotReceiverOrArbiter,
    InvalidOperator
} from "../../types/Errors.sol";

/**
 * @title RefundRequestAccess
 * @notice Access control for RefundRequest - reads directly from PaymentInfo
 * @dev Escrow is source of truth - no stored state validation needed
 */
abstract contract RefundRequestAccess {

    // ============ Payer Modifiers ============

    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    // ============ Combined Modifiers ============

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

    modifier validOperator(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator == address(0)) revert InvalidOperator();
        _;
    }

    // ============ Escrow State Helpers ============

    function isInEscrow(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) public view returns (bool) {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        (, uint120 capturableAmount,) = operator.ESCROW().paymentState(paymentInfoHash);
        return capturableAmount > 0;
    }
}
