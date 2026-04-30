// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IHook} from "../IHook.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {OnlyOperator} from "../../../types/Errors.sol";

/**
 * @title HookCombinator
 * @notice Combinator that calls multiple hooks sequentially
 * @dev Similar to AndCondition/OrCondition but for hooks.
 *      Allows combining multiple hook behaviors in a single slot.
 *
 * USE CASES:
 *   - EscrowPeriod hook + PaymentIndexHook
 *   - Multiple analytics/logging hooks
 *   - Custom business logic + indexing
 *
 * PATTERN: Composition over inheritance
 *          - Hooks are independent, reusable components
 *          - No order dependencies (all hooks get called)
 *          - If any hook reverts, entire transaction reverts
 *
 * GAS COST: ~1k per additional hook (external call overhead)
 *           Base cost: first hook cost
 *           Each additional: +1k for CALL + hook logic
 *
 * EXAMPLE:
 *   IHook[] memory hooks = new IHook[](2);
 *   hooks[0] = escrowPeriodHook;
 *   hooks[1] = paymentIndexHook;
 *   HookCombinator combinator = new HookCombinator(hooks);
 *
 *   operator = factory.deploy({
 *       AUTHORIZE_POST_ACTION_HOOK: address(combinator), // Both hooks!
 *       ...
 *   });
 */
contract HookCombinator is IHook {
    /// @notice Array of hooks to call
    IHook[] public hooks;

    /// @notice Maximum number of hooks to prevent excessive gas costs
    uint256 public constant MAX_POST_ACTION_HOOKS = 10;

    error EmptyHooks();
    error TooManyHooks(uint256 count, uint256 max);
    error ZeroHook(uint256 index);

    /**
     * @notice Creates a combinator with multiple hooks
     * @param _hooks Array of hook addresses to call
     */
    constructor(IHook[] memory _hooks) {
        if (_hooks.length == 0) revert EmptyHooks();
        if (_hooks.length > MAX_POST_ACTION_HOOKS) {
            revert TooManyHooks(_hooks.length, MAX_POST_ACTION_HOOKS);
        }

        // Validate no zero addresses
        for (uint256 i = 0; i < _hooks.length; i++) {
            if (address(_hooks[i]) == address(0)) revert ZeroHook(i);
        }

        hooks = _hooks;
    }

    /**
     * @notice Calls run() on all configured hooks sequentially
     * @param paymentInfo Payment information to forward
     * @param amount Amount involved in the action
     * @param caller Address that executed the action
     * @dev Reverts if any hook reverts
     */
    function run(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller,
        bytes calldata data
    ) external override {
        if (msg.sender != paymentInfo.operator) revert OnlyOperator();

        uint256 length = hooks.length;
        for (uint256 i = 0; i < length; i++) {
            hooks[i].run(paymentInfo, amount, caller, data);
        }
    }

    /**
     * @notice Returns the array of hooks
     * @return Array of hook addresses
     */
    function getHooks() external view returns (IHook[] memory) {
        return hooks;
    }

    /**
     * @notice Returns the number of hooks
     * @return Number of hooks in this combinator
     */
    function getHookCount() external view returns (uint256) {
        return hooks.length;
    }
}
