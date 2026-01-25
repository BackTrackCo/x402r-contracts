// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title AlwaysTrueCondition
/// @notice A condition that always returns true
/// @dev Useful for actions that should be allowed without any conditions
contract AlwaysTrueCondition is ICondition {
    /// @notice Always returns true
    /// @return allowed Always true
    function check(AuthCaptureEscrow.PaymentInfo calldata, address) external pure override returns (bool allowed) {
        return true;
    }
}
