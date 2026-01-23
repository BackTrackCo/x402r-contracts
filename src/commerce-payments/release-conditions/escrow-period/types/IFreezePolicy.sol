// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IFreezePolicy
 * @notice Interface for contracts that define freeze/unfreeze authorization policies.
 * @dev The freeze state itself is owned by EscrowPeriodCondition.
 *      This interface only determines WHO can freeze/unfreeze a payment.
 */
interface IFreezePolicy {
    /**
     * @notice Check if a caller is authorized to freeze a payment
     * @param paymentInfo The payment to freeze
     * @param caller The address attempting to freeze
     * @return True if the caller is authorized to freeze
     */
    function canFreeze(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) external view returns (bool);

    /**
     * @notice Check if a caller is authorized to unfreeze a payment
     * @param paymentInfo The payment to unfreeze
     * @param caller The address attempting to unfreeze
     * @return True if the caller is authorized to unfreeze
     */
    function canUnfreeze(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) external view returns (bool);
}
