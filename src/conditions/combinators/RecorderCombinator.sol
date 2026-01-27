// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IRecorder} from "../IRecorder.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title RecorderCombinator
 * @notice Combinator that calls multiple recorders sequentially
 * @dev Similar to AndCondition/OrCondition but for recorders.
 *      Allows combining multiple recorder behaviors in a single slot.
 *
 * USE CASES:
 *   - EscrowPeriodRecorder + PaymentIndexRecorder
 *   - Multiple analytics/logging recorders
 *   - Custom business logic + indexing
 *
 * PATTERN: Composition over inheritance
 *          - Recorders are independent, reusable components
 *          - No order dependencies (all recorders get called)
 *          - If any recorder reverts, entire transaction reverts
 *
 * GAS COST: ~1k per additional recorder (external call overhead)
 *           Base cost: first recorder cost
 *           Each additional: +1k for CALL + recorder logic
 *
 * EXAMPLE:
 *   IRecorder[] memory recorders = new IRecorder[](2);
 *   recorders[0] = escrowPeriodRecorder;
 *   recorders[1] = paymentIndexRecorder;
 *   RecorderCombinator combinator = new RecorderCombinator(recorders);
 *
 *   operator = factory.deploy({
 *       AUTHORIZE_RECORDER: address(combinator), // Both recorders!
 *       ...
 *   });
 */
contract RecorderCombinator is IRecorder {
    /// @notice Array of recorders to call
    IRecorder[] public recorders;

    /// @notice Maximum number of recorders to prevent excessive gas costs
    uint256 public constant MAX_RECORDERS = 10;

    error EmptyRecorders();
    error TooManyRecorders(uint256 count, uint256 max);
    error ZeroRecorder(uint256 index);

    /**
     * @notice Creates a combinator with multiple recorders
     * @param _recorders Array of recorder addresses to call
     */
    constructor(IRecorder[] memory _recorders) {
        if (_recorders.length == 0) revert EmptyRecorders();
        if (_recorders.length > MAX_RECORDERS) revert TooManyRecorders(_recorders.length, MAX_RECORDERS);

        // Validate no zero addresses
        for (uint256 i = 0; i < _recorders.length; i++) {
            if (address(_recorders[i]) == address(0)) revert ZeroRecorder(i);
        }

        recorders = _recorders;
    }

    /**
     * @notice Calls record() on all configured recorders sequentially
     * @param paymentInfo Payment information to record
     * @param amount Amount involved in the action
     * @param caller Address that executed the action
     * @dev Reverts if any recorder reverts
     */
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        override
    {
        uint256 length = recorders.length;
        for (uint256 i = 0; i < length; i++) {
            recorders[i].record(paymentInfo, amount, caller);
        }
    }

    /**
     * @notice Returns the array of recorders
     * @return Array of recorder addresses
     */
    function getRecorders() external view returns (IRecorder[] memory) {
        return recorders;
    }

    /**
     * @notice Returns the number of recorders
     * @return Number of recorders in this combinator
     */
    function getRecorderCount() external view returns (uint256) {
        return recorders.length;
    }
}
