// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    NotReceiver,
    NotPayer,
    NotArbiter,
    NotReceiverOrArbiter,
    InvalidOperator
} from "../../types/Errors.sol";
import {UnauthorizedCaller} from "../types/Errors.sol";

/**
 * @title ArbitrationOperatorAccess
 * @notice Stateless access control modifiers for payment operations
 * @dev Modifiers read directly from PaymentInfo struct and passed parameters - no state dependencies.
 *      Reusable across ArbitrationOperator, RefundRequest, and release conditions.
 */
abstract contract ArbitrationOperatorAccess {

    // ============ Receiver (Merchant) Modifiers ============

    /**
     * @notice Modifier to check if sender is the receiver
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver) revert NotReceiver();
        _;
    }

    // ============ Payer Modifiers ============

    /**
     * @notice Modifier to check if sender is the payer
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    // ============ Arbiter Modifiers ============

    /**
     * @notice Modifier to check if sender is the arbiter
     * @param arbiter The arbiter address
     */
    modifier onlyArbiter(address arbiter) {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    // ============ Combined Modifiers ============

    /**
     * @notice Modifier to check if sender is receiver or arbiter
     * @param paymentInfo The PaymentInfo struct
     * @param arbiter The arbiter address
     */
    modifier onlyReceiverOrArbiter(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address arbiter) {
        if (msg.sender != paymentInfo.receiver && msg.sender != arbiter) {
            revert NotReceiverOrArbiter();
        }
        _;
    }

    /**
     * @notice Modifier to check if sender is an authorized address or the payer
     * @param paymentInfo The PaymentInfo struct
     * @param authorized The authorized address (e.g., release condition contract)
     */
    modifier onlyAuthorizedOrPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address authorized) {
        if (msg.sender != authorized && msg.sender != paymentInfo.payer) {
            revert UnauthorizedCaller();
        }
        _;
    }

    // ============ Operator Validation ============

    /**
     * @notice Modifier to validate operator is this contract
     * @param paymentInfo The PaymentInfo struct
     */
    modifier validOperator(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator != address(this)) revert InvalidOperator();
        _;
    }
}
