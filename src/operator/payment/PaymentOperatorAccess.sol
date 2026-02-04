// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {InvalidFeeReceiver} from "../types/Errors.sol";

/**
 * @title PaymentOperatorAccess
 * @notice Stateless access control modifiers for PaymentOperator
 * @dev Contains ONLY modifiers used by PaymentOperator itself.
 *      For RefundRequest-specific modifiers, see RefundRequestAccess.
 *
 *      Note: validOperator check is NOT needed here because AuthCaptureEscrow
 *      already enforces msg.sender == paymentInfo.operator via onlySender modifier.
 */
abstract contract PaymentOperatorAccess {
    /**
     * @notice Modifier to validate fee receiver is this contract
     * @dev Ensures feeReceiver == address(this) so fees accumulate on the operator
     * @param paymentInfo The PaymentInfo struct to validate
     */
    modifier validFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        _checkValidFees(paymentInfo);
        _;
    }

    function _checkValidFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view {
        if (paymentInfo.feeReceiver != address(this)) revert InvalidFeeReceiver();
    }
}
