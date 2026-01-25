// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    NotReceiver,
    NotPayer,
    NotArbiter,
    InvalidOperator
} from "../../types/Errors.sol";
import {InvalidFeeBps, InvalidFeeReceiver} from "../types/Errors.sol";

/**
 * @title ArbitrationOperatorAccess
 * @notice Stateless access control modifiers for ArbitrationOperator
 * @dev Modifiers used by the operator contract itself.
 *
 *      Guard Modifiers (AND logic - reverts if not met):
 *      - validOperator: Ensures paymentInfo.operator == address(this)
 *      - onlyReceiver, onlyPayer, onlyArbiter: Require specific msg.sender
 */
abstract contract ArbitrationOperatorAccess {

    // ============ Guard Modifiers (AND logic) ============

    /**
     * @notice Modifier to validate operator is this contract
     * @dev Used by operator functions to ensure paymentInfo is for this operator
     * @param paymentInfo The PaymentInfo struct
     */
    modifier validOperator(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.operator != address(this)) revert InvalidOperator();
        _;
    }

    /**
     * @notice Modifier to check if sender is the receiver
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyReceiver(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.receiver) revert NotReceiver();
        _;
    }

    /**
     * @notice Modifier to check if sender is the payer
     * @param paymentInfo The PaymentInfo struct
     */
    modifier onlyPayer(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (msg.sender != paymentInfo.payer) revert NotPayer();
        _;
    }

    /**
     * @notice Modifier to check if sender is the arbiter
     * @param arbiter The arbiter address
     */
    modifier onlyArbiter(address arbiter) {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    /**
     * @notice Modifier to validate fee configuration in PaymentInfo
     * @dev Ensures minFeeBps == maxFeeBps == maxTotalFeeRate and feeReceiver == address(this)
     * @param paymentInfo The PaymentInfo struct to validate
     * @param maxTotalFeeRate The expected fee rate for both minFeeBps and maxFeeBps
     */
    modifier validFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 maxTotalFeeRate) {
        if (paymentInfo.minFeeBps != maxTotalFeeRate || paymentInfo.maxFeeBps != maxTotalFeeRate) {
            revert InvalidFeeBps();
        }
        if (paymentInfo.feeReceiver != address(this)) revert InvalidFeeReceiver();
        _;
    }
}
