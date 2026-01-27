// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// ============ Arbitration Operator Events ============
event AuthorizationCreated(
    bytes32 indexed paymentInfoHash, address indexed payer, address indexed receiver, uint256 amount, uint256 timestamp
);

event ReleaseExecuted(AuthCaptureEscrow.PaymentInfo paymentInfo, uint256 amount, uint256 timestamp);

event ChargeExecuted(
    bytes32 indexed paymentInfoHash, address indexed payer, address indexed receiver, uint256 amount, uint256 timestamp
);

event RefundExecuted(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer, uint256 amount);

event RefundAfterEscrowExecuted(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed payer, uint256 amount);

event FeesDistributed(address indexed token, uint256 protocolAmount, uint256 arbiterAmount);

// ============ Factory Events ============
event OperatorDeployed(address indexed operator, address indexed arbiter, address indexed releaseCondition);
