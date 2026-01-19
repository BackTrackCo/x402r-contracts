// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    NotReceiver,
    NotPayer,
    NotReceiverOrArbiter,
    PaymentDoesNotExist,
    InvalidOperator,
    NotInEscrow,
    NotCaptured,
    ZeroEscrow,
    ZeroArbiter
} from "./Errors.sol";

/**
 * @title ArbitrationOperatorAccess
 * @notice Access control for ArbitrationOperator using hash-based interface
 * @dev Provides modifiers for merchant (receiver), arbiter, and payer access control.
 *      Owns the state (ESCROW, ARBITER, paymentInfos) that child contracts inherit.
 */
abstract contract ArbitrationOperatorAccess {
    // State owned by this contract
    AuthCaptureEscrow public immutable ESCROW;
    address public immutable ARBITER;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public paymentInfos;

    constructor(address _escrow, address _arbiter) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_arbiter == address(0)) revert ZeroArbiter();
        ESCROW = AuthCaptureEscrow(_escrow);
        ARBITER = _arbiter;
    }

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

    /**
     * @notice Modifier for refund status updates - in escrow allows receiver OR arbiter, post-escrow only receiver
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyAuthorizedForRefundStatus(bytes32 paymentInfoHash) {
        address receiver = paymentInfos[paymentInfoHash].receiver;
        (, uint120 capturableAmount,) = ESCROW.paymentState(paymentInfoHash);

        if (capturableAmount > 0) {
            // In escrow: receiver OR arbiter can update
            if (msg.sender != receiver && msg.sender != ARBITER) {
                revert NotReceiverOrArbiter();
            }
        } else {
            // Post-escrow: only receiver can update
            if (msg.sender != receiver) {
                revert NotReceiver();
            }
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
     * @notice Internal function to check payment exists
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    function _requirePaymentExists(bytes32 paymentInfoHash) internal view {
        if (!paymentExists(paymentInfoHash)) revert PaymentDoesNotExist();
    }

    /**
     * @notice Modifier to check payment exists
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier paymentMustExist(bytes32 paymentInfoHash) {
        _requirePaymentExists(paymentInfoHash);
        _;
    }

    // ============ Escrow State Helpers ============

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
     * @notice Internal function to require payment is in escrow
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    function _onlyInEscrow(bytes32 paymentInfoHash) internal view {
        if (!isInEscrow(paymentInfoHash)) revert NotInEscrow();
    }

    /**
     * @notice Modifier to require payment is in escrow
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyInEscrow(bytes32 paymentInfoHash) {
        _onlyInEscrow(paymentInfoHash);
        _;
    }

    /**
     * @notice Internal function to require payment has been captured
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    function _onlyPostEscrow(bytes32 paymentInfoHash) internal view {
        (,, uint120 refundableAmount) = ESCROW.paymentState(paymentInfoHash);
        if (refundableAmount == 0) revert NotCaptured();
    }

    /**
     * @notice Modifier to require payment has been captured
     * @param paymentInfoHash The hash of the PaymentInfo
     */
    modifier onlyPostEscrow(bytes32 paymentInfoHash) {
        _onlyPostEscrow(paymentInfoHash);
        _;
    }
}
