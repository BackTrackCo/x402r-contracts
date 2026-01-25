// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ICanCondition} from "../../operator/types/ICanCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title PayerOnly
 * @notice Default condition that only allows the payer to perform an action
 * @dev Singleton - deploy once and reuse across all operators.
 *      Commonly used for CAN_RELEASE to implement payer bypass.
 */
contract PayerOnly is ICanCondition {
    /**
     * @notice Check if the caller is the payer
     * @param paymentInfo The PaymentInfo struct
     * @param caller The address attempting the action
     * @return True if caller is the payer
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256, /* amount */
        address caller
    ) external pure returns (bool) {
        return caller == paymentInfo.payer;
    }
}
