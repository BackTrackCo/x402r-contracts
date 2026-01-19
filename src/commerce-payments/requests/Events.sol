// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RequestStatus} from "./Types.sol";

// ============ Refund Request Events ============
event RefundRequested(
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    string ipfsLink
);

event RefundRequestStatusUpdated(
    bytes32 indexed paymentInfoHash,
    RequestStatus oldStatus,
    RequestStatus newStatus,
    address indexed updatedBy
);

event RefundRequestCancelled(
    bytes32 indexed paymentInfoHash,
    address indexed payer
);
