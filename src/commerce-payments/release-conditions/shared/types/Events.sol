// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Emitted when the payer bypasses the release condition
/// @param paymentInfo The PaymentInfo struct
/// @param payer Address of the payer who triggered the bypass
event PayerBypassTriggered(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer);
