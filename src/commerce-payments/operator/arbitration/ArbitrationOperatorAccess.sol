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
 * @dev Provides modifiers for merchant (receiver), arbiter, and payer access control.
 */
abstract contract ArbitrationOperatorAccess is ArbitrationOperatorState {
    constructor(address _escrow, address _arbiter) ArbitrationOperatorState(_escrow, _arbiter) {}

    // ============ Receiver (Merchant) Modifiers ============

    /**
     * @notice Modifier to check if sender is the receiver using hash lookup
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyReceiverByHash(bytes32 paymentInfoHash) {
        if (msg.sender != paymentInfos[paymentInfoHash].receiver) revert NotReceiver();
        _;
    }

    // ============ Payer Modifiers ============

    /**
     * @notice Modifier to check if sender is the payer using hash lookup
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyPayerByHash(bytes32 paymentInfoHash) {
        if (msg.sender != paymentInfos[paymentInfoHash].payer) revert NotPayer();
        _;
    }

    // ============ Combined Modifiers ============

    /**
     * @notice Modifier to check if sender is receiver or arbiter using hash lookup
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyReceiverOrArbiterByHash(bytes32 paymentInfoHash) {
        if (msg.sender != paymentInfos[paymentInfoHash].receiver && msg.sender != ARBITER) {
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

    /**
     * @notice Modifier to validate operator using hash lookup
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier validOperatorByHash(bytes32 paymentInfoHash) {
        if (paymentInfos[paymentInfoHash].operator != address(this)) revert InvalidOperator();
        _;
    }

    // ============ Payment Existence ============

    /**
     * @notice Modifier to check payment exists
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier paymentMustExist(bytes32 paymentInfoHash) {
        _requirePaymentExists(paymentInfoHash);
        _;
    }
}

