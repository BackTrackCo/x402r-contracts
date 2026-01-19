// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Arbitration Operator Events ============
event AuthorizationCreated(
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    address indexed receiver,
    uint256 amount,
    uint256 timestamp
);

event ReleaseExecuted(
    bytes32 indexed paymentInfoHash,
    uint256 amount,
    uint256 timestamp
);

event EarlyReleaseExecuted(
    bytes32 indexed paymentInfoHash,
    address indexed receiver,
    uint256 amount,
    uint256 timestamp
);

event RefundExecuted(
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    uint256 amount
);

event RefundAfterEscrowExecuted(
    bytes32 indexed paymentInfoHash,
    address indexed payer,
    uint256 amount
);

event ProtocolFeesEnabledUpdated(bool enabled);

event FeesDistributed(
    address indexed token,
    uint256 protocolAmount,
    uint256 arbiterAmount
);

// ============ Factory Events ============
event OperatorDeployed(
    address indexed operator,
    address indexed arbiter,
    uint48 escrowPeriod
);
