// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title ICondition
/// @notice Interface for checking if an action is allowed before execution
/// @dev Conditions are pure checks - they do not modify state.
///      Conditions can be composed using combinators (Or, And, Not).
///
///      IMPORTANT: Implementations MUST NOT revert. Return false to deny access.
///      Reverting conditions cause permanent DoS on non-receiver refund request updates
///      and break combinator short-circuit logic. Condition slots are immutable on
///      operators, so a reverting condition cannot be replaced.
interface ICondition {
    /// @notice Check if an action is allowed
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action (0 when used for authorization-only checks
    ///        such as refund request status updates, where no specific amount is relevant)
    /// @param caller The address attempting the action
    /// @return allowed True if the action is allowed
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        view
        returns (bool allowed);
}
