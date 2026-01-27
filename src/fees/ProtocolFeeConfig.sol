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
    error NoPendingRecipientChange();
    error RecipientTimelockNotElapsed();

    // ============ Events ============
    event CalculatorChangeQueued(address indexed newCalculator, uint256 executeAfter);
    event CalculatorChangeExecuted(address indexed newCalculator);
    event CalculatorChangeCancelled();
    event RecipientChangeQueued(address indexed newRecipient, uint256 executeAfter);
    event RecipientChangeExecuted(address indexed newRecipient);
    event RecipientChangeCancelled();

    // ============ Constants ============
    uint256 public constant TIMELOCK_DELAY = 7 days;

    // ============ State ============
    IFeeCalculator public calculator;
    address public protocolFeeRecipient;

    // ============ Timelock State ============
    address public pendingCalculator;
    uint256 public pendingCalculatorTimestamp;
    address public pendingRecipient;
    uint256 public pendingRecipientTimestamp;

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

    // ============ Owner Functions: Recipient Timelock ============

    /// @notice Queue a recipient change (7-day timelock)
    /// @param _protocolFeeRecipient New fee recipient (must not be address(0))
    function queueRecipient(address _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert();
        pendingRecipient = _protocolFeeRecipient;
        pendingRecipientTimestamp = block.timestamp + TIMELOCK_DELAY;
        emit RecipientChangeQueued(_protocolFeeRecipient, pendingRecipientTimestamp);
    }

    /// @notice Execute a queued recipient change after timelock
    function executeRecipient() external onlyOwner {
        if (pendingRecipientTimestamp == 0) revert NoPendingRecipientChange();
        if (block.timestamp < pendingRecipientTimestamp) revert RecipientTimelockNotElapsed();

        protocolFeeRecipient = pendingRecipient;
        emit RecipientChangeExecuted(pendingRecipient);

        pendingRecipient = address(0);
        pendingRecipientTimestamp = 0;
    }

    /// @notice Cancel a pending recipient change
    function cancelRecipient() external onlyOwner {
        if (pendingRecipientTimestamp == 0) revert NoPendingRecipientChange();
        pendingRecipient = address(0);
        pendingRecipientTimestamp = 0;
        emit RecipientChangeCancelled();
    }

    // ============ Owner Functions: Calculator Timelock ============

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
