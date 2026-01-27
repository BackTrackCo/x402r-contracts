// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IFeeCalculator} from "./IFeeCalculator.sol";

/**
 * @title ProtocolFeeConfig
 * @notice Shared protocol fee configuration contract read by all operators.
 *         Owned by protocol multisig. Holds a swappable IFeeCalculator with 7-day timelock
 *         and a protocol fee recipient address.
 *
 * OWNERSHIP: Uses Solady's Ownable with built-in 2-step transfer for safety:
 *        1. New owner calls requestOwnershipHandover()
 *        2. Current owner calls completeOwnershipHandover(newOwner) within 48 hours
 *
 * PRODUCTION REQUIREMENT: Owner MUST be a multisig (e.g., Gnosis Safe) in production.
 */
contract ProtocolFeeConfig is Ownable {
    // ============ Errors ============
    error NoPendingCalculatorChange();
    error CalculatorTimelockNotElapsed();

    // ============ Events ============
    event CalculatorChangeQueued(address indexed newCalculator, uint256 executeAfter);
    event CalculatorChangeExecuted(address indexed newCalculator);
    event CalculatorChangeCancelled();
    event ProtocolFeeRecipientUpdated(address indexed newRecipient);

    // ============ Constants ============
    uint256 public constant TIMELOCK_DELAY = 7 days;

    // ============ State ============
    IFeeCalculator public calculator;
    address public protocolFeeRecipient;

    // ============ Timelock State ============
    address public pendingCalculator;
    uint256 public pendingCalculatorTimestamp;

    constructor(address _calculator, address _protocolFeeRecipient, address _owner) {
        if (_owner == address(0)) revert();
        if (_protocolFeeRecipient == address(0)) revert();
        _initializeOwner(_owner);
        calculator = IFeeCalculator(_calculator);
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    // ============ View Functions ============

    /// @notice Get protocol fee in basis points for a payment action
    /// @dev Returns 0 if calculator is address(0)
    function getProtocolFeeBps(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        view
        returns (uint256)
    {
        if (address(calculator) == address(0)) return 0;
        return calculator.calculateFee(paymentInfo, amount, caller);
    }

    /// @notice Get the protocol fee recipient address
    function getProtocolFeeRecipient() external view returns (address) {
        return protocolFeeRecipient;
    }

    // ============ Owner Functions ============

    /// @notice Set the protocol fee recipient address
    /// @param _protocolFeeRecipient New fee recipient
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert();
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    /// @notice Queue a calculator change (7-day timelock)
    /// @param _calculator New calculator address (address(0) = disable protocol fees)
    function queueCalculator(address _calculator) external onlyOwner {
        pendingCalculator = _calculator;
        pendingCalculatorTimestamp = block.timestamp + TIMELOCK_DELAY;
        emit CalculatorChangeQueued(_calculator, pendingCalculatorTimestamp);
    }

    /// @notice Execute a queued calculator change after timelock
    function executeCalculator() external onlyOwner {
        if (pendingCalculatorTimestamp == 0) revert NoPendingCalculatorChange();
        if (block.timestamp < pendingCalculatorTimestamp) revert CalculatorTimelockNotElapsed();

        calculator = IFeeCalculator(pendingCalculator);
        emit CalculatorChangeExecuted(pendingCalculator);

        pendingCalculator = address(0);
        pendingCalculatorTimestamp = 0;
    }

    /// @notice Cancel a pending calculator change
    function cancelCalculator() external onlyOwner {
        if (pendingCalculatorTimestamp == 0) revert NoPendingCalculatorChange();
        pendingCalculator = address(0);
        pendingCalculatorTimestamp = 0;
        emit CalculatorChangeCancelled();
    }
}
