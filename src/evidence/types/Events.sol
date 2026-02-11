// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {SubmitterRole} from "./Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// ============ Evidence Events ============
event EvidenceSubmitted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    uint256 nonce,
    address indexed submitter,
    SubmitterRole role,
    string cid,
    uint256 index
);
