// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025-2026 Ali Abdoli and Vrajang Parikh
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";

/// @notice Forward declaration to read arbiter from operator
interface IArbitrationOperator {
    function ARBITER() external view returns (address);
}

/// @title ArbiterCondition
/// @notice Checks if the caller is the arbiter of the operator
/// @dev Reads arbiter from the operator contract via forward declaration
contract ArbiterCondition is ICondition {
    /// @notice Check if caller is the arbiter
    /// @param paymentInfo The payment information (contains operator address)
    /// @param caller The address attempting the action
    /// @return allowed True if caller is the arbiter
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool allowed)
    {
        address arbiter = IArbitrationOperator(paymentInfo.operator).ARBITER();
        return caller == arbiter;
    }
}
