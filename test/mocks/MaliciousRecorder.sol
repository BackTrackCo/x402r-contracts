// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecorder} from "../../src/conditions/IRecorder.sol";
import {IOperator} from "../../src/operator/types/IOperator.sol";
import {PaymentOperator} from "../../src/operator/arbitration/PaymentOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MaliciousRecorder
 * @notice Mock recorder that attempts reentrancy attacks for testing
 * @dev Used to verify reentrancy protection in operators
 */
contract MaliciousRecorder is IRecorder {
    enum AttackType {
        NONE,
        REENTER_SAME_FUNCTION, // Try to call the same function again
        REENTER_DIFFERENT_FUNCTION, // Try to call a different function
        REENTER_WITHDRAW_FEES, // Try to withdraw fees during callback
        INFINITE_LOOP // Consume all gas
    }

    AttackType public attackType;
    IOperator public targetOperator;
    AuthCaptureEscrow.PaymentInfo public storedPaymentInfo;
    uint256 public storedAmount;
    uint256 public reentrancyCount;
    uint256 public maxReentrancy = 1;

    constructor(AttackType _attackType) {
        attackType = _attackType;
    }

    function setAttackType(AttackType _attackType) external {
        attackType = _attackType;
    }

    function setMaxReentrancy(uint256 _max) external {
        maxReentrancy = _max;
    }

    /**
     * @notice Malicious record function that attempts reentrancy
     */
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        override
    {
        // Store for potential reuse
        storedPaymentInfo = paymentInfo;
        storedAmount = amount;
        targetOperator = IOperator(msg.sender);

        // Increment counter
        reentrancyCount++;

        // Execute attack based on type
        if (attackType == AttackType.REENTER_SAME_FUNCTION && reentrancyCount <= maxReentrancy) {
            // Try to reenter the same function with same payment
            // This should fail because escrow rejects duplicate operations
            try targetOperator.release(paymentInfo, amount) {
                // If this succeeds, it's a vulnerability!
            } catch {
                // Expected - reentrancy should be blocked
            }
        } else if (attackType == AttackType.REENTER_DIFFERENT_FUNCTION && reentrancyCount <= maxReentrancy) {
            // Try to call a different function during callback
            // Create a new payment for refund attempt
            try targetOperator.refundPostEscrow(paymentInfo, uint120(amount), address(0), "") {
                // If this succeeds when it shouldn't, it's a vulnerability
            } catch {
                // Expected in most cases
            }
        } else if (attackType == AttackType.REENTER_WITHDRAW_FEES && reentrancyCount <= maxReentrancy) {
            // Try to distribute fees during callback (note: distributeFees is not access-controlled)
            try PaymentOperator(payable(msg.sender)).distributeFees(paymentInfo.token) {
                // If this succeeds and causes accounting issues, it's a vulnerability
            } catch {
                // May succeed or fail depending on state
            }
        } else if (attackType == AttackType.INFINITE_LOOP) {
            // Gas griefing attack - consume all available gas
            // Note: In production, this would cause the entire transaction to revert
            uint256 counter = 0;
            while (gasleft() > 10000) {
                counter++;
                if (counter > 100000) break; // Safety limit for testing
            }
        }
    }

    /**
     * @notice Reset reentrancy counter for next test
     */
    function reset() external {
        reentrancyCount = 0;
    }

    /**
     * @notice Manually trigger attack for testing
     */
    function triggerAttack() external {
        if (attackType == AttackType.REENTER_SAME_FUNCTION) {
            targetOperator.release(storedPaymentInfo, storedAmount);
        }
    }
}
