// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title PayerCondition
/// @notice Checks if the caller is the payer of the payment
/// @dev Stateless - reads payer directly from paymentInfo
contract PayerCondition is ICondition {
    /// @notice Check if caller is the payer
    /// @param paymentInfo The payment information
    /// @param caller The address attempting the action
    /// @return allowed True if caller is the payer
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address caller)
        external
        pure
        override
        returns (bool allowed)
    {
        return caller == paymentInfo.payer;
    }
}
