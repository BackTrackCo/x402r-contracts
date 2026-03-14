// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Emitted when a payment's authorization time is recorded
/// @param paymentInfo The PaymentInfo struct
event AuthorizationRecorded(AuthCaptureEscrow.PaymentInfo paymentInfo);

/// @notice Emitted when an EscrowPeriod contract is deployed via factory
/// @param escrowPeriod Address of the deployed EscrowPeriod contract
/// @param escrowPeriodDuration Duration of the escrow period in seconds
event EscrowPeriodDeployed(address indexed escrowPeriod, uint256 escrowPeriodDuration);
