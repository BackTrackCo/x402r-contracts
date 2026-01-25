# x402r Contracts

[![CI](https://github.com/x402r/x402r-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/x402r/x402r-contracts/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/x402r/x402r-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/x402r/x402r-contracts)

## Deployed Contracts

⚠️ **WARNING: CONTRACTS UNAUDITED - USE AT YOUR OWN RISK**

These contracts have been deployed but have **not been audited**. 
Users should exercise extreme caution and conduct thorough due diligence before 
interacting with these contracts. The developers assume no liability for any 
losses incurred from using these contracts.

### Base Sepolia

**Source of truth:** This README. Addresses will eventually be moved to `@x402r/sdk` package.

#### Core Contracts

| Contract | Address |
|----------|---------|
| AuthCaptureEscrow | [`0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8`](https://sepolia.basescan.org/address/0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8) |
| ERC3009PaymentCollector | [`0xed02d3E5167BCc9582D851885A89b050AB816a56`](https://sepolia.basescan.org/address/0xed02d3E5167BCc9582D851885A89b050AB816a56) |
| RefundRequest | [`0x26A3d27139b442Be5ECc10c8608c494627B660BF`](https://sepolia.basescan.org/address/0x26A3d27139b442Be5ECc10c8608c494627B660BF) |

#### Factories

| Contract | Address |
|----------|---------|
| ArbitrationOperatorFactory | [`0x46C44071BDf9753482400B76d88A5850318b776F`](https://sepolia.basescan.org/address/0x46C44071BDf9753482400B76d88A5850318b776F) |
| EscrowPeriodConditionFactory | [`0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178`](https://sepolia.basescan.org/address/0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178) |
| FreezePolicyFactory | [`0x536439b00002CB3c0141391A92aFBB3e1E3f8604`](https://sepolia.basescan.org/address/0x536439b00002CB3c0141391A92aFBB3e1E3f8604) |

#### Condition Singletons (for use with FreezePolicyFactory)

| Contract | Address |
|----------|---------|
| PayerCondition | [`0xDc0D800007ceACFf1299b926Ce22B4d4edCE6Ce7`](https://sepolia.basescan.org/address/0xDc0D800007ceACFf1299b926Ce22B4d4edCE6Ce7) |
| ReceiverCondition | [`0x138Bf828643350AA3692aedDE8b2254eDF4D07EF`](https://sepolia.basescan.org/address/0x138Bf828643350AA3692aedDE8b2254eDF4D07EF) |
| ArbiterCondition | [`0x32471D31910a009273A812dE0894d9f0ADef4834`](https://sepolia.basescan.org/address/0x32471D31910a009273A812dE0894d9f0ADef4834) |
| AlwaysTrueCondition | [`0xe2659dc0d716B1226DF6a09A5f47862cd1ff6733`](https://sepolia.basescan.org/address/0xe2659dc0d716B1226DF6a09A5f47862cd1ff6733) |

**USDC (Base Sepolia):** [`0x036CbD53842c5426634e7929541eC2318f3dCF7e`](https://sepolia.basescan.org/address/0x036CbD53842c5426634e7929541eC2318f3dCF7e)

### Project Contracts

This repository contains contracts for the x402r refund extension system.

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERACTIONS                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Payer                    Receiver                   Arbiter                │
│    │                         │                          │                   │
│    │  authorize()            │  release()               │  refund*()        │
│    │  freeze()               │                          │  updateStatus()   │
│    │  requestRefund()        │                          │                   │
└────┼─────────────────────────┼──────────────────────────┼───────────────────┘
     │                         │                          │
     ▼                         ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ARBITRATION OPERATOR                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Condition Slots (before action)    Recorder Slots (after action)   │   │
│  │  ─────────────────────────────────  ─────────────────────────────   │   │
│  │  AUTHORIZE_CONDITION ──────────────► AUTHORIZE_RECORDER             │   │
│  │  CHARGE_CONDITION ─────────────────► CHARGE_RECORDER                │   │
│  │  RELEASE_CONDITION ────────────────► RELEASE_RECORDER               │   │
│  │  REFUND_IN_ESCROW_CONDITION ───────► REFUND_IN_ESCROW_RECORDER      │   │
│  │  REFUND_POST_ESCROW_CONDITION ─────► REFUND_POST_ESCROW_RECORDER    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  Owner Functions (24h Timelock):   │                                        │
│  - queueFeesEnabled()              │                                        │
│  - executeFeesEnabled()            │                                        │
│  - cancelFeesEnabled()             │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AUTH CAPTURE ESCROW                                  │
│                    (Base Commerce Payments)                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Payment State Machine:                                              │   │
│  │                                                                      │   │
│  │  NonExistent ──authorize()──► InEscrow ──release()──► Released      │   │
│  │                                  │                        │          │   │
│  │                     void/reclaim │      refundPostEscrow  │          │   │
│  │                     refundInEscrow                        │          │   │
│  │                                  ▼                        ▼          │   │
│  │                            ┌─────────────────────────────────┐      │   │
│  │                            │           Settled               │      │   │
│  │                            └─────────────────────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Condition Combinator Pattern

Conditions are composable plugins that control access to operator actions:

```
┌──────────────────────────────────────────────────────────────────┐
│                     CONDITION COMBINATORS                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  AndCondition([A, B, C])  ──►  A && B && C                       │
│  OrCondition([A, B])      ──►  A || B                            │
│  NotCondition(A)          ──►  !A                                │
│                                                                   │
│  Example: Release requires (Receiver OR Arbiter) AND EscrowPassed│
│                                                                   │
│  OrCondition([                                                   │
│    ReceiverCondition,                                            │
│    ArbiterCondition                                              │
│  ])                                                              │
│    └──► AndCondition([                                           │
│           <above>,                                               │
│           EscrowPeriodCondition                                  │
│         ])                                                       │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Escrow Period & Freeze Flow

```
Timeline:
├─────────────── ESCROW_PERIOD (e.g., 7 days) ───────────────┼──── Post-Escrow ────►
│                                                             │
│  [Payer can freeze]                                        │  [Release allowed]
│  [Release blocked]                                         │  [Freeze blocked]
│                                                             │
│  freeze() ──► PaymentFrozen                                │
│  unfreeze() ──► PaymentUnfrozen                            │
│                                                             │
└─────────────────────────────────────────────────────────────┴─────────────────────►

MEV Protection: Payers should freeze EARLY, not at deadline.
                Use private mempool (Flashbots Protect) if freezing near expiry.
```

### Contract Relationships

```
┌─────────────────────────┐
│ ArbitrationOperatorFactory │◄─── Owner (Multisig in production)
└────────────┬────────────┘
             │ deploys
             ▼
┌─────────────────────────┐      ┌─────────────────────────┐
│  ArbitrationOperator    │─────►│    AuthCaptureEscrow    │
│  (per-arbiter instance) │      │   (shared singleton)    │
└────────────┬────────────┘      └─────────────────────────┘
             │ uses
             ▼
┌─────────────────────────────────────────────────────────────┐
│                    PLUGGABLE CONDITIONS                      │
├─────────────────────────────────────────────────────────────┤
│  Access Conditions:          │  Time Conditions:            │
│  - PayerCondition            │  - EscrowPeriodCondition     │
│  - ReceiverCondition         │    └─► EscrowPeriodRecorder  │
│  - ArbiterCondition          │        └─► PayerFreezePolicy │
│  - AlwaysTrueCondition       │                              │
├─────────────────────────────────────────────────────────────┤
│  Combinators:                │  Auxiliary:                  │
│  - AndCondition              │  - RefundRequest             │
│  - OrCondition               │                              │
│  - NotCondition              │                              │
└─────────────────────────────────────────────────────────────┘
```

### Roles & Permissions

| Role | Capabilities |
|------|-------------|
| **Payer** | `authorize()`, `freeze()`, `unfreeze()`, `requestRefund()`, `cancelRefundRequest()` |
| **Receiver** | `release()` (if condition allows), `charge()` |
| **Arbiter** | `refundInEscrow()`, `refundPostEscrow()`, `updateStatus()` on refund requests |
| **Owner** | `queueFeesEnabled()`, `executeFeesEnabled()`, `cancelFeesEnabled()`, `rescueETH()` |

### Security Features

| Feature | Implementation |
|---------|---------------|
| **Reentrancy Protection** | `ReentrancyGuardTransient` on escrow |
| **CEI Pattern** | All functions: Checks → Effects → Interactions |
| **2-Step Ownership** | Solady's `requestOwnershipHandover()` + `completeOwnershipHandover()` |
| **24h Timelock** | Fee changes require queue → wait → execute |
| **Multisig Requirement** | Owner must be Gnosis Safe in production |
| **Incident Response** | See [SECURITY.md](SECURITY.md) |

#### Commerce Payments Contracts

The commerce-payments contracts provide refund functionality for Base Commerce Payments authorizations:

- **ArbitrationOperator**: `src/commerce-payments/operator/ArbitrationOperator.sol`
  - Operator contract that wraps Base Commerce Payments and enforces refund delay for uncaptured funds, arbiter refund restrictions, and fee distribution.

- **RefundRequest**: `src/commerce-payments/requests/refund/RefundRequest.sol`
  - Contract for managing refund requests for Base Commerce Payments authorizations. Users can create refund requests, cancel their own pending requests, and merchants or arbiters can approve or deny them based on capture status.

#### Freeze Policy Options

The `EscrowPeriodRecorder` contract supports an optional freeze policy via the `FREEZE_POLICY` parameter. This determines who can freeze/unfreeze payments during the escrow period.

**FreezePolicy** uses `ICondition` contracts for authorization:

| Condition | Description |
|-----------|-------------|
| `PayerCondition` | Allows the payment's payer |
| `ReceiverCondition` | Allows the payment's receiver |
| `ArbiterCondition` | Allows the operator's arbiter |
| `AlwaysTrueCondition` | Allows anyone |

**Example:**

```solidity
// Payer freeze/unfreeze, 3-day duration
freezePolicyFactory.deploy(payerCondition, payerCondition, 3 days);

// Payer freeze, Arbiter unfreeze, permanent
freezePolicyFactory.deploy(payerCondition, arbiterCondition, 0);

// Anyone freeze, Receiver unfreeze, 7 days
freezePolicyFactory.deploy(alwaysTrueCondition, receiverCondition, 7 days);
```

**Note:** If `FREEZE_POLICY` is `address(0)` when deploying EscrowPeriodRecorder, freeze/unfreeze calls will revert with `NoFreezePolicy()` error.

#### ArbitrationOperatorFactory API

The `ArbitrationOperatorFactory` provides a single generic `deployOperator(OperatorConfig)` method. There are no convenience methods - users must construct the full `OperatorConfig` struct:

```solidity
struct OperatorConfig {
    address arbiter;
    address authorizeCondition;
    address authorizeRecorder;
    address releaseCondition;
    address releaseRecorder;
    address refundInEscrowCondition;
    address refundInEscrowRecorder;
    address refundPostEscrowCondition;
    address refundPostEscrowRecorder;
}
```

**Example: Deploy a simple operator (all conditions = address(0))**
```solidity
ArbitrationOperatorFactory.OperatorConfig memory config = ArbitrationOperatorFactory.OperatorConfig({
    arbiter: arbiterAddress,
    authorizeCondition: address(0),
    authorizeRecorder: address(0),
    releaseCondition: address(0),
    releaseRecorder: address(0),
    refundInEscrowCondition: address(0),
    refundInEscrowRecorder: address(0),
    refundPostEscrowCondition: address(0),
    refundPostEscrowRecorder: address(0)
});
address operator = factory.deployOperator(config);
```

**Note:** `address(0)` for a condition means "allow all" (no restriction). `address(0)` for a recorder means "no-op" (no state recording).

#### Factory Deployment

All deployment scripts use factory contracts that provide:
- **Deterministic addresses (CREATE2)**: Same inputs = same address, even if not yet deployed
- **Idempotent deployment**: Safe to call multiple times, returns existing if already deployed
- **Shared configuration**: Escrow, protocol fees set once in factory
- **Centralized owner control**: Factory owner controls all deployed instances

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Setup

### Environment Variables

1. Copy the example environment file:
   ```shell
   cp .env.example .env
   ```

2. Edit `.env` and add your API keys:
   ```shell
   ETHERSCAN_API_KEY=your_basescan_api_key_here
   PRIVATE_KEY=your_private_key_here
   ```

   Get your Basescan API key from: https://basescan.org/myapikey

3. Load environment variables before running commands:
   ```shell
   source .env
   ```

   Or export them manually:
   ```shell
   export ETHERSCAN_API_KEY=your_api_key
   export PRIVATE_KEY=your_private_key
   ```

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Deploy contracts using the deployment scripts. The `--verify` flag will automatically verify contracts on Basescan using the `ETHERSCAN_API_KEY` from your `.env` file.

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
