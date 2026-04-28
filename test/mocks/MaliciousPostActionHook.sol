// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPostActionHook} from "../../src/plugins/post-action-hooks/IPostActionHook.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MaliciousPostActionHook
 * @notice Mock hook that attempts reentrancy attacks for testing
 * @dev Used to verify reentrancy protection in operators. The hook can be configured
 *      to re-enter a specific action (Authorize/Capture/Void/Refund/Charge), which is
 *      what each `test_ReentrancyOnX_SameFunction` exercises.
 */
contract MaliciousPostActionHook is IPostActionHook {
    enum AttackType {
        NONE,
        REENTER_SAME_FUNCTION, // Try to re-enter the action configured via TargetAction
        REENTER_DIFFERENT_FUNCTION, // Try to call a different function
        REENTER_WITHDRAW_FEES, // Try to withdraw fees during callback
        INFINITE_LOOP // Consume all gas
    }

    /// @notice Which action the hook attempts to re-enter under REENTER_SAME_FUNCTION.
    /// @dev Independent from the slot the hook is installed in: tests sometimes configure
    ///      the malicious hook on slot N but want it to re-enter action M for cross-slot
    ///      attacks. For "true" same-function reentry, set TargetAction to match the slot.
    enum TargetAction {
        AUTHORIZE,
        CAPTURE,
        VOID,
        REFUND,
        CHARGE
    }

    AttackType public attackType;
    TargetAction public targetAction;
    PaymentOperator public targetOperator;
    AuthCaptureEscrow.PaymentInfo public storedPaymentInfo;
    uint256 public reentrancyCount;
    uint256 public maxReentrancy = 1;
    bool public reentrancyBlocked;

    constructor(AttackType _attackType) {
        attackType = _attackType;
        targetAction = TargetAction.CAPTURE; // backwards-compat default
    }

    function setAttackType(AttackType _attackType) external {
        attackType = _attackType;
    }

    function setTargetAction(TargetAction _targetAction) external {
        targetAction = _targetAction;
    }

    function setMaxReentrancy(uint256 _max) external {
        maxReentrancy = _max;
    }

    function run(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address, bytes calldata)
        external
        override
    {
        storedPaymentInfo = paymentInfo;
        targetOperator = PaymentOperator(msg.sender);

        reentrancyCount++;

        if (attackType == AttackType.REENTER_SAME_FUNCTION && reentrancyCount <= maxReentrancy) {
            _reenterTargetAction(paymentInfo, amount);
        } else if (attackType == AttackType.REENTER_DIFFERENT_FUNCTION && reentrancyCount <= maxReentrancy) {
            // Try to call a different function during callback (always refund here).
            try targetOperator.refund(paymentInfo, amount, address(0), "") {
            // If this succeeds when it shouldn't, the guard failed.
            }
            catch {
                reentrancyBlocked = true;
            }
        } else if (attackType == AttackType.REENTER_WITHDRAW_FEES && reentrancyCount <= maxReentrancy) {
            try PaymentOperator(payable(msg.sender)).distributeFees(paymentInfo.token) {
            // distributeFees is also nonReentrant; should revert.
            }
            catch {
                reentrancyBlocked = true;
            }
        } else if (attackType == AttackType.INFINITE_LOOP) {
            uint256 counter = 0;
            while (gasleft() > 10000) {
                counter++;
                if (counter > 100000) break;
            }
        }
    }

    function _reenterTargetAction(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) internal {
        if (targetAction == TargetAction.AUTHORIZE) {
            try targetOperator.authorize(paymentInfo, amount, address(0), "") {
            // re-entry succeeded; the test asserts on `reentrancyBlocked` to detect.
            }
            catch {
                reentrancyBlocked = true;
            }
        } else if (targetAction == TargetAction.CAPTURE) {
            try targetOperator.capture(paymentInfo, amount, "") {}
            catch {
                reentrancyBlocked = true;
            }
        } else if (targetAction == TargetAction.VOID) {
            try targetOperator.void(paymentInfo, "") {}
            catch {
                reentrancyBlocked = true;
            }
        } else if (targetAction == TargetAction.REFUND) {
            try targetOperator.refund(paymentInfo, amount, address(0), "") {}
            catch {
                reentrancyBlocked = true;
            }
        } else if (targetAction == TargetAction.CHARGE) {
            try targetOperator.charge(paymentInfo, amount, address(0), "") {}
            catch {
                reentrancyBlocked = true;
            }
        }
    }

    function reset() external {
        reentrancyCount = 0;
        reentrancyBlocked = false;
    }

    function triggerAttack() external {
        targetOperator.capture(storedPaymentInfo, storedPaymentInfo.maxAmount, "");
    }
}
