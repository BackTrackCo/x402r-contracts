// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {InvalidOperator} from "../../types/Errors.sol";
import {InvalidFeeReceiver} from "../types/Errors.sol";

/**
 * @title PaymentOperatorAccess
 * @notice Stateless access control modifiers for PaymentOperator
 * @dev Contains ONLY modifiers used by PaymentOperator itself.
 *      For RefundRequest-specific modifiers, see RefundRequestAccess.
 */
abstract contract PaymentOperatorAccess {
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
     * @notice Modifier to validate fee receiver is this contract
     * @dev Ensures feeReceiver == address(this) so fees accumulate on the operator
     * @param paymentInfo The PaymentInfo struct to validate
     */
    modifier validFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) {
        if (paymentInfo.feeReceiver != address(this)) revert InvalidFeeReceiver();
        _;
    }
}
