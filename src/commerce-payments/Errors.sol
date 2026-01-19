// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Common Errors ============
error ZeroAddress();
error ZeroAmount();

// ============ Access Control Errors ============
error NotReceiver();
error NotPayer();
error NotReceiverOrArbiter();

// ============ Payment State Errors ============
error PaymentDoesNotExist();
error InvalidOperator();
error NotInEscrow();
error NotCaptured();

// ============ Refund Request Errors ============
error EmptyIpfsLink();
error RequestAlreadyExists();
error RequestDoesNotExist();
error RequestNotPending();
error InvalidStatus();
error FullyRefunded();

// ============ Operator Errors ============
error ZeroOperator();
error ZeroEscrow();
error ZeroArbiter();
error RefundPeriodNotPassed();
error TotalFeeRateExceedsMax();

// ============ Factory Errors ============
error ZeroRefundPeriod();
