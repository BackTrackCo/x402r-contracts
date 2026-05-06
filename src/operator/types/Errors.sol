// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Operator-Specific Errors ============
error ZeroEscrow();

// ============ PaymentInfo Validation Errors ============
error InvalidFeeReceiver();

// ============ Fee Errors ============
error FeeTooHigh();
error FeeBoundsIncompatible(uint16 calculatedFeeBps, uint16 minFeeBps, uint16 maxFeeBps);

// ============ Pre-Action Condition Errors ============
error PreActionConditionNotMet();
