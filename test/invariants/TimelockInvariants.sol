// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";

/**
 * @title TimelockInvariants
 * @notice Echidna property-based testing for ProtocolFeeConfig timelock integrity.
 * @dev Verifies that calculator and recipient changes cannot be executed before
 *      the 7-day timelock delay elapses.
 *
 * Usage:
 *   echidna . --contract TimelockInvariants --config echidna.yaml
 */
contract TimelockInvariants is Test {
    ProtocolFeeConfig public config;
    StaticFeeCalculator public initialCalc;
    StaticFeeCalculator public pendingCalc;

    // Ghost state for tracking invariants
    address public queuedCalculator;
    uint256 public queuedCalculatorTimestamp;
    bool public executedCalculatorBefore7Days;

    address public queuedRecipient;
    uint256 public queuedRecipientTimestamp;
    bool public executedRecipientBefore7Days;

    constructor() {
        initialCalc = new StaticFeeCalculator(100); // 1%
        pendingCalc = new StaticFeeCalculator(200); // 2%

        config = new ProtocolFeeConfig(address(initialCalc), address(this), address(this));
    }

    // ============ Calculator Timelock Entry Points ============

    function queueCalculator_fuzz() public {
        config.queueCalculator(address(pendingCalc));
        queuedCalculator = address(pendingCalc);
        queuedCalculatorTimestamp = block.timestamp;
    }

    function executeCalculator_early_fuzz(uint256 delta) public {
        if (queuedCalculatorTimestamp == 0) return;

        // Warp to before the 7-day timelock
        delta = bound(delta, 0, 7 days - 1);
        vm.warp(queuedCalculatorTimestamp + delta);

        try config.executeCalculator() {
            // If execution succeeded before 7 days, record violation
            executedCalculatorBefore7Days = true;
        } catch {
            // Expected: should revert with CalculatorTimelockNotElapsed
        }
    }

    function executeCalculator_late_fuzz(uint256 delta) public {
        if (queuedCalculatorTimestamp == 0) return;

        // Warp to after the 7-day timelock
        delta = bound(delta, 7 days, 60 days);
        vm.warp(queuedCalculatorTimestamp + delta);

        try config.executeCalculator() {
            // Reset ghost state after successful execution
            queuedCalculator = address(0);
            queuedCalculatorTimestamp = 0;
        } catch {}
    }

    function cancelCalculator_fuzz() public {
        try config.cancelCalculator() {
            queuedCalculator = address(0);
            queuedCalculatorTimestamp = 0;
        } catch {}
    }

    // ============ Recipient Timelock Entry Points ============

    function queueRecipient_fuzz() public {
        address newRecipient = address(uint160(uint256(keccak256(abi.encode(block.timestamp, block.number)))));
        if (newRecipient == address(0)) newRecipient = address(0xBEEF);

        config.queueRecipient(newRecipient);
        queuedRecipient = newRecipient;
        queuedRecipientTimestamp = block.timestamp;
    }

    function executeRecipient_early_fuzz(uint256 delta) public {
        if (queuedRecipientTimestamp == 0) return;

        // Warp to before the 7-day timelock
        delta = bound(delta, 0, 7 days - 1);
        vm.warp(queuedRecipientTimestamp + delta);

        try config.executeRecipient() {
            // If execution succeeded before 7 days, record violation
            executedRecipientBefore7Days = true;
        } catch {
            // Expected: should revert with RecipientTimelockNotElapsed
        }
    }

    function executeRecipient_late_fuzz(uint256 delta) public {
        if (queuedRecipientTimestamp == 0) return;

        // Warp to after the 7-day timelock
        delta = bound(delta, 7 days, 60 days);
        vm.warp(queuedRecipientTimestamp + delta);

        try config.executeRecipient() {
            // Reset ghost state after successful execution
            queuedRecipient = address(0);
            queuedRecipientTimestamp = 0;
        } catch {}
    }

    function cancelRecipient_fuzz() public {
        try config.cancelRecipient() {
            queuedRecipient = address(0);
            queuedRecipientTimestamp = 0;
        } catch {}
    }

    // ============ Time Manipulation ============

    function warpTime_fuzz(uint256 delta) public {
        if (delta == 0 || delta > 60 days) return;
        vm.warp(block.timestamp + delta);
    }

    // ============ Echidna Invariants ============

    /// @notice Calculator cannot be executed before 7-day timelock elapses
    function echidna_calculator_execute_before_7_days_always_fails() public view returns (bool) {
        return !executedCalculatorBefore7Days;
    }

    /// @notice Recipient cannot be changed before 7-day timelock elapses
    function echidna_recipient_execute_before_7_days_always_fails() public view returns (bool) {
        return !executedRecipientBefore7Days;
    }

    /// @notice Timelock delay constant is always 7 days
    function echidna_timelock_delay_is_7_days() public view returns (bool) {
        return config.TIMELOCK_DELAY() == 7 days;
    }
}
