// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    PaymentAlreadyRegistered,
    NotPayer
} from "./types/Errors.sol";
import {PaymentRegistered, PayerBypassTriggered} from "./types/Events.sol";

/**
 * @title EscrowPeriodCondition
 * @notice Release condition that enforces a time-based escrow period before funds can be released.
 *         The payer can optionally bypass the escrow period to allow immediate release.
 *
 * @dev Key features:
 *      - Operator-agnostic: works with any ArbitrationOperator
 *      - Funds locked for ESCROW_PERIOD seconds after registration
 *      - Payer can call payerBypass() to waive the wait and allow immediate release
 *      - Functions take PaymentInfo directly - escrow is source of truth
 */
contract EscrowPeriodCondition is IReleaseCondition {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Stores the end time for each payment
    /// @dev Key: paymentInfoHash (derived from PaymentInfo)
    mapping(bytes32 => uint256) public escrowEndTimes;

    /// @notice Tracks which payments have been bypassed by the payer
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public payerBypassed;

    constructor(uint256 _escrowPeriod) {
        ESCROW_PERIOD = _escrowPeriod;
    }

    /**
     * @notice Register a payment to start its escrow period
     * @param paymentInfo PaymentInfo struct from the operator
     * @dev Can be called by anyone. Sets escrowEndTime = block.timestamp + ESCROW_PERIOD
     */
    function registerPayment(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        bytes32 paymentInfoHash = _getHash(paymentInfo);

        // Prevent double registration
        if (escrowEndTimes[paymentInfoHash] != 0) revert PaymentAlreadyRegistered();

        uint256 endTime = block.timestamp + ESCROW_PERIOD;
        escrowEndTimes[paymentInfoHash] = endTime;

        emit PaymentRegistered(paymentInfoHash, endTime);
    }

    /**
     * @notice Payer bypasses the escrow period to allow immediate release
     * @param paymentInfo PaymentInfo struct from the operator
     * @dev Only the payer of the payment can call this
     */
    function payerBypass(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        if (msg.sender != paymentInfo.payer) revert NotPayer();

        bytes32 paymentInfoHash = _getHash(paymentInfo);
        payerBypassed[paymentInfoHash] = true;

        emit PayerBypassTriggered(paymentInfoHash, msg.sender);
    }

    /**
     * @notice Check if a payment can be released (called by ArbitrationOperator)
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount being released (unused in this condition, for future extensibility)
     * @return True if escrow period has passed OR payer has bypassed
     */
    function canRelease(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external view override returns (bool) {
        // Silence unused variable warning
        amount;

        bytes32 paymentInfoHash = _getHash(paymentInfo);

        // If payer has bypassed, allow release immediately
        if (payerBypassed[paymentInfoHash]) {
            return true;
        }

        // Check if payment has been registered
        uint256 endTime = escrowEndTimes[paymentInfoHash];
        if (endTime == 0) {
            return false; // Not registered yet
        }

        // Check if escrow period has passed
        return block.timestamp >= endTime;
    }

    /**
     * @notice Get the escrow end time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the escrow period expires (0 if not registered)
     */
    function getEscrowEndTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return escrowEndTimes[_getHash(paymentInfo)];
    }

    /**
     * @notice Check if a payment has been bypassed by the payer
     * @param paymentInfo PaymentInfo struct
     * @return True if the payer has bypassed the escrow period
     */
    function isPayerBypassed(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return payerBypassed[_getHash(paymentInfo)];
    }

    /**
     * @notice Internal helper to compute hash from PaymentInfo
     * @dev Uses the operator's escrow to compute the canonical hash
     */
    function _getHash(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view returns (bytes32) {
        return ArbitrationOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo);
    }
}
