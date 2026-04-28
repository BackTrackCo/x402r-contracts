// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title IPostActionHook
/// @notice Interface for hooks that run after an action is executed
/// @dev Hooks are called after an action succeeds, typically to update state.
///      Amount and caller are provided for convenience; hooks may ignore them.
///      Amount can also be deduced from escrow state (capturableAmount, refundableAmount).
interface IPostActionHook {
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
