// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title IRecorder
/// @notice Interface for recording state after an action is executed
/// @dev Recorders are called after an action succeeds to update state.
///      Amount and caller are provided for convenience - recorders may ignore them.
///      Amount can also be deduced from escrow state (capturableAmount, refundableAmount).
interface IRecorder {
    /// @notice Record state after an action is executed
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action
    /// @param caller The address that executed the action (msg.sender on operator)
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller) external;
}
