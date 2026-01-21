// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

/// @notice Emitted when a payment is authorized through the escrow period condition
/// @param paymentInfoHash Hash of the PaymentInfo struct
/// @param authorizationTime Timestamp when the payment was authorized
event PaymentAuthorized(bytes32 indexed paymentInfoHash, uint256 authorizationTime);

/// @notice Emitted when the payer bypasses the escrow period
/// @param paymentInfoHash Hash of the PaymentInfo struct
/// @param payer Address of the payer who triggered the bypass
event PayerBypassTriggered(bytes32 indexed paymentInfoHash, address indexed payer);

/// @notice Emitted when escrow period condition is deployed via factory
/// @param condition Address of the deployed condition contract
/// @param escrowPeriod Duration of the escrow period in seconds
event EscrowPeriodConditionDeployed(address indexed condition, uint256 escrowPeriod);
