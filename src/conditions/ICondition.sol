// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title ICondition
/// @notice Interface for checking if an action is allowed before execution
/// @dev Conditions are pure checks - they do not modify state
/// @dev Conditions can be composed using combinators (Or, And, Not)
interface ICondition {
    /// @notice Check if an action is allowed
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action
    /// @param caller The address attempting the action
    /// @return allowed True if the action is allowed
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        view
        returns (bool allowed);
}
