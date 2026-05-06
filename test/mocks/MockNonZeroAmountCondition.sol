// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title MockNonZeroAmountCondition
/// @notice Pre-action condition that gates on `amount > 0`. Used to verify that
///         operator action methods pass a meaningful amount to the condition rather
///         than a hardcoded 0 — particularly for void(), where passing 0 would
///         silently bypass any amount-based gating logic.
contract MockNonZeroAmountCondition is ICondition {
    function check(AuthCaptureEscrow.PaymentInfo calldata, uint256 amount, address, bytes calldata)
        external
        pure
        override
        returns (bool allowed)
    {
        return amount > 0;
    }
}
