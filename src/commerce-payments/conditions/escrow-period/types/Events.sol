// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Emitted when a payment's authorization time is recorded
/// @param paymentInfo The PaymentInfo struct
/// @param authorizationTime Timestamp when the payment was authorized
event AuthorizationTimeRecorded(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 authorizationTime);

/// @notice Emitted when a payment is frozen
/// @param paymentInfo The PaymentInfo struct
/// @param caller The address that froze the payment
event PaymentFrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);

/// @notice Emitted when a payment is unfrozen
/// @param paymentInfo The PaymentInfo struct
/// @param caller The address that unfroze the payment
event PaymentUnfrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);

/// @notice Emitted when escrow period condition is deployed via factory
/// @param condition Address of the deployed condition contract
/// @param recorder Address of the deployed recorder contract
/// @param escrowPeriod Duration of the escrow period in seconds
event EscrowPeriodConditionDeployed(address indexed condition, address indexed recorder, uint256 escrowPeriod);
