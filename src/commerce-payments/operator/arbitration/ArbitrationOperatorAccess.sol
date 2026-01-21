// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperatorState} from "./ArbitrationOperatorState.sol";
import {
    NotReceiver,
    NotPayer,
    NotReceiverOrArbiter,
    InvalidOperator
} from "../../types/Errors.sol";

/**
 * @title ArbitrationOperatorAccess
 * @notice Access control modifiers for ArbitrationOperator
 * @dev Modifiers read directly from PaymentInfo struct - escrow is source of truth
 */
abstract contract ArbitrationOperatorAccess is ArbitrationOperatorState {
    constructor(address _escrow, address _arbiter) ArbitrationOperatorState(_escrow, _arbiter) {}

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

    // ============ Combined Modifiers ============

    /**
     * @notice Modifier to check if sender is receiver or arbiter
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyReceiverOrArbiter(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver && msg.sender != ARBITER) {
            revert NotReceiverOrArbiter();
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
