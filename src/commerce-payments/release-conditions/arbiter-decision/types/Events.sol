// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";



/// @notice Emitted when the arbiter approves a payment release
/// @param paymentInfo The PaymentInfo struct
/// @param arbiter Address of the arbiter who approved
event ArbiterApproved(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed arbiter);
