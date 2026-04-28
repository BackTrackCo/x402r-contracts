// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IPreActionCondition} from "../IPreActionCondition.sol";

/// @title AlwaysTruePreActionCondition
/// @notice A condition that always returns true
/// @dev Useful for actions that should be allowed without any conditions
contract AlwaysTruePreActionCondition is IPreActionCondition {
    /// @notice Always returns true
    /// @return allowed Always true
    function check(AuthCaptureEscrow.PaymentInfo calldata, uint256, address, bytes calldata)
        external
        pure
        override
        returns (bool allowed)
    {
        return true;
    }
}
