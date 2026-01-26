// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title ReceiverCondition
/// @notice Checks if the caller is the receiver of the payment
/// @dev Stateless - reads receiver directly from paymentInfo
contract ReceiverCondition is ICondition {
    /// @notice Check if caller is the receiver
    /// @param paymentInfo The payment information
    /// @param caller The address attempting the action
    /// @return allowed True if caller is the receiver
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        pure
        override
        returns (bool allowed)
    {
        return caller == paymentInfo.receiver;
    }
}
