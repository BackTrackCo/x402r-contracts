// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Operator-Specific Errors ============
error ZeroEscrow();
error TotalFeeRateExceedsMax();
error ReleaseLocked();

// ============ PaymentInfo Validation Errors ============
error InvalidFeeBps();
error InvalidFeeReceiver();
error UnauthorizedCaller();
error ETHTransferFailed();

// ============ Condition Errors ============
error ConditionNotMet();

// ============ Timelock Errors ============
error TimelockNotElapsed();
error NoPendingChange();

