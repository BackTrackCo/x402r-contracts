// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperator} from "../operator/ArbitrationOperator.sol";
import {
    ZeroOperator,
    NotReceiver,
    NotPayer,
    NotReceiverOrArbiter,
    PaymentDoesNotExist,
    InvalidOperator,
    NotInEscrow,
    NotCaptured
} from "../Errors.sol";

/**
 * @title RefundRequestAccess
 * @notice Access control for RefundRequest that delegates to ArbitrationOperator
 * @dev All access checks query OPERATOR for state
 */
abstract contract RefundRequestAccess {
    ArbitrationOperator public immutable OPERATOR;

    constructor(address _operator) {
        if (_operator == address(0)) revert ZeroOperator();
        OPERATOR = ArbitrationOperator(_operator);
    }

    // ============ Receiver (Merchant) Modifiers ============

    modifier onlyReceiverByHash(bytes32 paymentInfoHash) {
        if (msg.sender != OPERATOR.getPaymentInfo(paymentInfoHash).receiver) revert NotReceiver();
        _;
    }

    // ============ Payer Modifiers ============

    modifier onlyPayerByHash(bytes32 paymentInfoHash) {
        if (msg.sender != OPERATOR.getPaymentInfo(paymentInfoHash).payer) revert NotPayer();
        _;
    }

    // ============ Combined Modifiers ============

    modifier onlyReceiverOrArbiterByHash(bytes32 paymentInfoHash) {
        if (msg.sender != OPERATOR.getPaymentInfo(paymentInfoHash).receiver && msg.sender != OPERATOR.ARBITER()) {
            revert NotReceiverOrArbiter();
        }
        _;
    }

    modifier onlyAuthorizedForRefundStatus(bytes32 paymentInfoHash) {
        address receiver = OPERATOR.getPaymentInfo(paymentInfoHash).receiver;
        (, uint120 capturableAmount,) = OPERATOR.ESCROW().paymentState(paymentInfoHash);

        if (capturableAmount > 0) {
            if (msg.sender != receiver && msg.sender != OPERATOR.ARBITER()) {
                revert NotReceiverOrArbiter();
            }
        } else {
            if (msg.sender != receiver) {
                revert NotReceiver();
            }
        }
        _;
    }

    // ============ Operator Validation ============

    modifier validOperatorByHash(bytes32 paymentInfoHash) {
        if (OPERATOR.getPaymentInfo(paymentInfoHash).operator != address(OPERATOR)) revert InvalidOperator();
        _;
    }

    // ============ Payment Existence ============

    modifier paymentMustExist(bytes32 paymentInfoHash) {
        if (!OPERATOR.paymentExists(paymentInfoHash)) revert PaymentDoesNotExist();
        _;
    }

    // ============ Escrow State Helpers ============

    function isInEscrow(bytes32 paymentInfoHash) public view returns (bool) {
        (, uint120 capturableAmount,) = OPERATOR.ESCROW().paymentState(paymentInfoHash);
        return capturableAmount > 0;
    }

    modifier onlyInEscrow(bytes32 paymentInfoHash) {
        if (!isInEscrow(paymentInfoHash)) revert NotInEscrow();
        _;
    }

    modifier onlyPostEscrow(bytes32 paymentInfoHash) {
        (,, uint120 refundableAmount) = OPERATOR.ESCROW().paymentState(paymentInfoHash);
        if (refundableAmount == 0) revert NotCaptured();
        _;
    }
}
