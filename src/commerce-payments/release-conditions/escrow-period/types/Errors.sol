// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

/// @notice Payment has already been registered
error PaymentAlreadyRegistered();

/// @notice Payment has not been registered
error PaymentNotRegistered();

/// @notice Caller is not the payer
error NotPayer();

/// @notice Invalid escrow period (zero)
error InvalidEscrowPeriod();
