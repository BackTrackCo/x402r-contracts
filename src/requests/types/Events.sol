// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RequestStatus} from "./Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// ============ Refund Request Events ============
event RefundRequested(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    address indexed payer,
    address indexed receiver,
    uint120 amount,
    uint256 nonce
);

event RefundRequestStatusUpdated(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    RequestStatus oldStatus,
    RequestStatus newStatus,
    address indexed updatedBy,
    uint256 nonce
);

event RefundRequestCancelled(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer, uint256 nonce);

// ============ Factory Events ============
event RefundRequestDeployed(address indexed refundRequest);
