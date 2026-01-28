// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @title NotCondition
/// @notice Negates a condition
/// @dev Returns true if the wrapped condition returns false
contract NotCondition is ICondition {
    /// @notice The condition to negate
    ICondition public immutable CONDITION;

    /// @notice Error when condition is zero address
    error ZeroCondition();

    /// @notice Create a NOT combinator
    /// @param _condition The condition to negate
    constructor(ICondition _condition) {
        if (address(_condition) == address(0)) revert ZeroCondition();
        CONDITION = _condition;
    }

    /// @notice Check the negation of the wrapped condition
    /// @param paymentInfo The payment information
    /// @param amount The amount involved in the action
    /// @param caller The address attempting the action
    /// @return allowed True if the wrapped condition returns false
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        view
        override
        returns (bool allowed)
    {
        return !CONDITION.check(paymentInfo, amount, caller);
    }
}
