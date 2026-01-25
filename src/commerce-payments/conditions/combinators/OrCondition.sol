// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title OrCondition
/// @notice Combines multiple conditions with OR logic
/// @dev Returns true if ANY condition returns true
/// @dev Short-circuits on first true result for gas efficiency
contract OrCondition is ICondition {
    /// @notice The conditions to check (OR logic)
    ICondition[] public conditions;

    /// @notice Error when no conditions are provided
    error NoConditions();

    /// @notice Create an OR combinator with multiple conditions
    /// @param _conditions Array of conditions to combine with OR logic
    constructor(ICondition[] memory _conditions) {
        if (_conditions.length == 0) revert NoConditions();
        for (uint256 i = 0; i < _conditions.length; i++) {
            conditions.push(_conditions[i]);
        }
    }

    /// @notice Check if ANY condition passes
    /// @param paymentInfo The payment information
    /// @param caller The address attempting the action
    /// @return allowed True if any condition returns true
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool allowed)
    {
        uint256 len = conditions.length;
        for (uint256 i = 0; i < len; i++) {
            if (conditions[i].check(paymentInfo, caller)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Get the number of conditions
    /// @return The number of conditions in this combinator
    function conditionCount() external view returns (uint256) {
        return conditions.length;
    }
}
