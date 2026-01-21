// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

/**
 * @title IReleaseCondition
 * @notice Interface for external release condition contracts
 * @dev Implement this interface to create custom release conditions.
 *      When set on an ArbitrationOperator, canRelease() is called during release()
 *      to determine if the receiver can capture funds.
 */
interface IReleaseCondition {
    /**
     * @notice Check if a payment can be released
     * @param paymentInfoHash Hash of the PaymentInfo struct
     * @return True if release is allowed, false to block
     */
    function canRelease(bytes32 paymentInfoHash) external view returns (bool);
}
