// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IFreezeChecker
 * @notice Interface for contracts that can freeze payments (e.g., during arbitration)
 */
interface IFreezeChecker {
    /**
     * @notice Check if a payment is frozen
     * @param paymentInfoHash The hash of the payment
     * @return True if the payment is frozen and release should be blocked
     */
    function isFrozen(bytes32 paymentInfoHash) external view returns (bool);
}
