// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Emitted when a payment is authorized through the escrow period condition
/// @param paymentInfo The PaymentInfo struct
/// @param authorizationTime Timestamp when the payment was authorized
event PaymentAuthorized(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 authorizationTime);



/// @notice Emitted when escrow period condition is deployed via factory
/// @param condition Address of the deployed condition contract
/// @param escrowPeriod Duration of the escrow period in seconds
event EscrowPeriodConditionDeployed(address indexed condition, uint256 escrowPeriod);
