// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RequestStatus} from "./Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// ============ Refund Request Events ============
event RefundRequested(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    address indexed payer,
    address indexed receiver
);

event RefundRequestStatusUpdated(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    RequestStatus oldStatus,
    RequestStatus newStatus,
    address indexed updatedBy
);

event RefundRequestCancelled(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    address indexed payer
);

// ============ Factory Events ============
event RefundRequestDeployed(
    address indexed refundRequest,
    address indexed operator
);
