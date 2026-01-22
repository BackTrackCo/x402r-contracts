// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IReleaseCondition
 * @notice Interface for external release condition contracts (push model)
 * @dev Implement this interface to create custom release conditions.
 *
 *      PUSH MODEL: The release condition contract is the ONLY address that can call
 *      operator.release(). Users call release() on the condition contract, which
 *      validates conditions and then calls the operator.
 */
interface IReleaseCondition {
    /**
     * @notice Release funds by calling the operator (push model entry point)
     * @dev Must validate conditions and call operator.release()
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount to release
     */
    function release(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external;
}
