// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title AndCondition
/// @notice Combines multiple conditions with AND logic
/// @dev Returns true only if ALL conditions return true
/// @dev Short-circuits on first false result for gas efficiency
contract AndCondition is ICondition {
    /// @notice Maximum number of conditions allowed to prevent gas griefing
    uint256 public constant MAX_CONDITIONS = 10;

    /// @notice The conditions to check (AND logic)
    ICondition[] public conditions;

    /// @notice Error when no conditions are provided
    error NoConditions();

    /// @notice Error when too many conditions are provided
    error TooManyConditions();

    /// @notice Create an AND combinator with multiple conditions
    /// @param _conditions Array of conditions to combine with AND logic
    constructor(ICondition[] memory _conditions) {
        if (_conditions.length == 0) revert NoConditions();
        if (_conditions.length > MAX_CONDITIONS) revert TooManyConditions();
        for (uint256 i = 0; i < _conditions.length; i++) {
            conditions.push(_conditions[i]);
        }
    }

    /// @notice Check if ALL conditions pass
    /// @param paymentInfo The payment information
    /// @param caller The address attempting the action
    /// @return allowed True only if all conditions return true
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool allowed)
    {
        uint256 len = conditions.length;
        for (uint256 i = 0; i < len; i++) {
            if (!conditions[i].check(paymentInfo, caller)) {
                return false;
            }
        }
        return true;
    }

    /// @notice Get the number of conditions
    /// @return The number of conditions in this combinator
    function conditionCount() external view returns (uint256) {
        return conditions.length;
    }
}
