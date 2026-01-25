// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title IRecorder
/// @notice Interface for recording state after an action is executed
/// @dev Recorders are called after an action succeeds to update state
/// @dev Unlike conditions, recorders CAN modify state
interface IRecorder {
    /// @notice Record state after an action is executed
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action
    /// @param caller The address that executed the action
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller) external;
}
