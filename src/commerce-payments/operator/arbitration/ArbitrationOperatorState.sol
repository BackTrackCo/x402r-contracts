// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ZeroEscrow, ZeroArbiter} from "../types/Errors.sol";

/**
 * @title ArbitrationOperatorState
 * @notice State management and view functions for ArbitrationOperator
 * @dev Holds core state (ESCROW, ARBITER, paymentInfos) and provides view functions.
 */
abstract contract ArbitrationOperatorState {
    // Core state
    AuthCaptureEscrow public immutable ESCROW;
    address public immutable ARBITER;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public paymentInfos;

    // Payment indexing for discoverability
    mapping(address => bytes32[]) private payerPayments;
    mapping(address => bytes32[]) private receiverPayments;

    constructor(address _escrow, address _arbiter) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_arbiter == address(0)) revert ZeroArbiter();
        ESCROW = AuthCaptureEscrow(_escrow);
        ARBITER = _arbiter;
    }

    // ============ View Functions ============

    /**
     * @notice Check if a payment exists (has been authorized)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment exists
     */
    function paymentExists(bytes32 paymentInfoHash) public view returns (bool) {
        return paymentInfos[paymentInfoHash].payer != address(0);
    }

    /**
     * @notice Get stored PaymentInfo for a given hash
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return The stored PaymentInfo struct
     */
    function getPaymentInfo(bytes32 paymentInfoHash) public view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return paymentInfos[paymentInfoHash];
    }

    /**
     * @notice Check if payment is in escrow (has capturable amount)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment is in escrow
     */
    function isInEscrow(bytes32 paymentInfoHash) public view returns (bool) {
        (, uint120 capturableAmount,) = ESCROW.paymentState(paymentInfoHash);
        return capturableAmount > 0;
    }

    /**
     * @notice Get all payment hashes for a payer
     * @param payer The payer address
     * @return Array of payment info hashes
     */
    function getPayerPayments(address payer) external view returns (bytes32[] memory) {
        return payerPayments[payer];
    }

    /**
     * @notice Get all payment hashes for a receiver (merchant)
     * @param receiver The receiver address
     * @return Array of payment info hashes
     */
    function getReceiverPayments(address receiver) external view returns (bytes32[] memory) {
        return receiverPayments[receiver];
    }

    // ============ Internal Helpers ============

    /**
     * @notice Add payment hash to payer's list
     * @param payer The payer address
     * @param hash The payment info hash
     */
    function _addPayerPayment(address payer, bytes32 hash) internal {
        payerPayments[payer].push(hash);
    }

    /**
     * @notice Add payment hash to receiver's list
     * @param receiver The receiver address
     * @param hash The payment info hash
     */
    function _addReceiverPayment(address receiver, bytes32 hash) internal {
        receiverPayments[receiver].push(hash);
    }
}
