// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// ============ Operator Action Events ============
event AuthorizeExecuted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    uint256 amount
);

event ChargeExecuted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    uint256 amount
);

event CaptureExecuted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    uint256 amount
);

event VoidExecuted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver
);

event RefundExecuted(
    AuthCaptureEscrow.PaymentInfo paymentInfo,
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    uint256 amount
);

event FeesDistributed(address indexed token, uint256 protocolAmount, uint256 operatorAmount);

// ============ Factory Events ============
event OperatorDeployed(address indexed operator, address indexed deployer, address indexed feeReceiver);
