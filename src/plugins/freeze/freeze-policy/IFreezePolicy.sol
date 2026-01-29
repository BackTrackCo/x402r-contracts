// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IFreezePolicy
 * @notice Interface for contracts that define freeze/unfreeze authorization policies.
 * @dev The freeze state itself is owned by the Freeze condition contract.
 *      This interface determines WHO can freeze/unfreeze and for HOW LONG.
 */
interface IFreezePolicy {
    /**
     * @notice Check if a caller is authorized to freeze a payment and get freeze duration
     * @param paymentInfo The payment to freeze
     * @param caller The address attempting to freeze
     * @return allowed True if the caller is authorized to freeze
     * @return duration How long the freeze should last in seconds (0 = permanent until unfrozen)
     */
    function canFreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        returns (bool allowed, uint256 duration);

    /**
     * @notice Check if a caller is authorized to unfreeze a payment
     * @param paymentInfo The payment to unfreeze
     * @param caller The address attempting to unfreeze
     * @return True if the caller is authorized to unfreeze
     */
    function canUnfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        returns (bool);
}
