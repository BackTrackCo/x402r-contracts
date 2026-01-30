// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Operator-Specific Errors ============
error ZeroEscrow();
error ReleaseLocked();

// ============ PaymentInfo Validation Errors ============
error InvalidFeeReceiver();
error UnauthorizedCaller();

// ============ Fee Errors ============
error FeeTooHigh();
error FeeBoundsIncompatible(uint16 calculatedFeeBps, uint16 minFeeBps, uint16 maxFeeBps);

// ============ Condition Errors ============
error ConditionNotMet();
