// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title IHook
/// @notice Interface for hooks that run after an action is executed
/// @dev Hooks are called after an action succeeds, typically to update state.
///      Amount and caller are provided for convenience; hooks may ignore them.
///      Amount can also be deduced from escrow state (capturableAmount, refundableAmount).
///
///      IMPORTANT: Hook business logic MUST NOT revert — use early-return for no-op
///      cases (e.g. RefundRequest returns early when no request exists, when the
///      request is not approvable, or when the capped amount is zero). A business-logic
///      revert causes permanent DoS on the surrounding action; hook slots are immutable
///      on PaymentOperator, so a reverting hook cannot be replaced. The pattern mirrors
///      ICondition's "MUST NOT revert" guidance.
///
///      Auth-layer reverts (e.g. BaseHook._verifyAndHash reverting with OnlyOperator
///      or PaymentDoesNotExist) are exempt from this rule: the only callers that can
///      trigger them are unauthorized ones, where reverting is the correct outcome.
interface IHook {
    /// @notice Run the hook after an action is executed
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action
    /// @param caller The address that executed the action (msg.sender on operator)
    /// @param data Arbitrary data forwarded from the caller (e.g. signatures, proofs, attestations)
    function run(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller,
        bytes calldata data
    ) external;
}
