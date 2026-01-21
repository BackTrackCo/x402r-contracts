// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

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
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount being released
     * @return True if release is allowed, false to block
     */
    function canRelease(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external view returns (bool);
}
