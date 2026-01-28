// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IRecorder} from "./IRecorder.sol";
import {OnlyOperator, ZeroAddress, PaymentDoesNotExist} from "../types/Errors.sol";

/**
 * @title BaseRecorder
 * @notice Abstract base for all recorders with operator verification and escrow existence checks.
 * @dev Subclasses implement IRecorder.record() and call _verifyAndHash() to get a validated
 *      payment hash. This prevents fake operators from poisoning recorder state, since
 *      paymentInfo.operator is part of the payment hash — a fake operator produces a hash
 *      that doesn't exist in the real escrow.
 *
 * SECURITY:
 *      - OnlyOperator: msg.sender must equal paymentInfo.operator, or msg.sender's
 *        runtime codehash must match AUTHORIZED_CODEHASH (e.g. RecorderCombinator)
 *      - Escrow existence: payment must exist in the trusted immutable ESCROW
 *      - Both checks together ensure only real operators recording real payments can write state
 */
abstract contract BaseRecorder is IRecorder {
    /// @notice Escrow contract for payment hash calculation and existence verification
    AuthCaptureEscrow public immutable ESCROW;

    /// @notice Runtime codehash of authorized caller contract (e.g. RecorderCombinator)
    /// @dev bytes32(0) means no authorized codehash — only the operator itself can call record().
    ///      Uses EXTCODEHASH to verify caller bytecode, which is unforgeable (unlike ERC-165).
    bytes32 public immutable AUTHORIZED_CODEHASH;

    constructor(address escrow, bytes32 authorizedCodehash) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
        AUTHORIZED_CODEHASH = authorizedCodehash;
    }

    /**
     * @notice Verify caller is the operator and payment exists in escrow
     * @dev Returns the payment hash for use by subclass record() implementations.
     *      Reverts with OnlyOperator if caller != paymentInfo.operator.
     *      Reverts with PaymentDoesNotExist if payment not found in escrow.
     * @param paymentInfo PaymentInfo struct
     * @return paymentHash The verified payment hash
     */
    function _verifyAndHash(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        internal
        view
        returns (bytes32 paymentHash)
    {
        if (
            msg.sender != paymentInfo.operator
                && (AUTHORIZED_CODEHASH == bytes32(0) || msg.sender.codehash != AUTHORIZED_CODEHASH)
        ) {
            revert OnlyOperator();
        }

        paymentHash = ESCROW.getHash(paymentInfo);

        (bool hasCollected, uint120 capturableAmount,) = ESCROW.paymentState(paymentHash);
        if (!hasCollected && capturableAmount == 0) revert PaymentDoesNotExist();
    }

    /**
     * @notice Internal helper to get payment hash without verification
     * @dev Used by subclass view functions and non-record operations (e.g. freeze/unfreeze)
     * @param paymentInfo PaymentInfo struct
     * @return Payment hash
     */
    function _getPaymentHash(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view returns (bytes32) {
        return ESCROW.getHash(paymentInfo);
    }
}
