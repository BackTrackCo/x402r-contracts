# x402r Contracts

[![CI](https://github.com/x402r/x402r-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/x402r/x402r-contracts/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/x402r/x402r-contracts/branch/main/graph/badge.svg)](https://codecov.io/gh/x402r/x402r-contracts)

## Deployed Contracts

⚠️ **WARNING: CONTRACTS UNAUDITED - USE AT YOUR OWN RISK**

These contracts have been deployed but have **not been audited**.
Users should exercise extreme caution and conduct thorough due diligence before
interacting with these contracts. The developers assume no liability for any
losses incurred from using these contracts.

## Documentation

For auditors and developers:

| Document | Description |
|----------|-------------|
| **[AUDIT.md](AUDIT.md)** | 📋 Comprehensive audit documentation (start here) |
| [SECURITY.md](SECURITY.md) | 🔒 Security overview and threat model |
| [OPERATOR_SECURITY.md](OPERATOR_SECURITY.md) | 🛡️ Operator-specific security considerations |
| [TOKENS.md](TOKENS.md) | 🪙 Token compatibility and handling |
| [FUZZING.md](FUZZING.md) | 🔬 Fuzzing methodology and invariants |
| [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) | ✅ Production deployment checklist |
| [GAS_BREAKDOWN.md](GAS_BREAKDOWN.md) | 📊 Detailed gas cost analysis |

### Base Sepolia

**Source of truth:** This README. Addresses will eventually be moved to `@x402r/sdk` package.

#### Core Contracts

| Contract | Address |
|----------|---------|
| **AuthCaptureEscrow** | [`0xb9488351E48b23D798f24e8174514F28B741Eb4f`](https://sepolia.basescan.org/address/0xb9488351E48b23D798f24e8174514F28B741Eb4f) |
| **PaymentOperator** | [`0xB47a37e754c1e159EE5ECAff6aa2D210D4C1A075`](https://sepolia.basescan.org/address/0xB47a37e754c1e159EE5ECAff6aa2D210D4C1A075) |
| RefundRequest | [`0x26A3d27139b442Be5ECc10c8608c494627B660BF`](https://sepolia.basescan.org/address/0x26A3d27139b442Be5ECc10c8608c494627B660BF) |

#### Factories

| Contract | Address |
|----------|---------|
| **PaymentOperatorFactory** | [`0x48ADf6E37F9b31dC2AAD0462C5862B5422C736B8`](https://sepolia.basescan.org/address/0x48ADf6E37F9b31dC2AAD0462C5862B5422C736B8) |
| EscrowPeriodConditionFactory | [`0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178`](https://sepolia.basescan.org/address/0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178) |
| FreezePolicyFactory | [`0x536439b00002CB3c0141391A92aFBB3e1E3f8604`](https://sepolia.basescan.org/address/0x536439b00002CB3c0141391A92aFBB3e1E3f8604) |

#### Condition Singletons

| Contract | Address | Status |
|----------|---------|--------|
| PayerCondition | [`0xDc0D800007ceACFf1299b926Ce22B4d4edCE6Ce7`](https://sepolia.basescan.org/address/0xDc0D800007ceACFf1299b926Ce22B4d4edCE6Ce7) | ✅ Active |
| ReceiverCondition | [`0x138Bf828643350AA3692aedDE8b2254eDF4D07EF`](https://sepolia.basescan.org/address/0x138Bf828643350AA3692aedDE8b2254eDF4D07EF) | ✅ Active |
| AlwaysTrueCondition | [`0xe2659dc0d716B1226DF6a09A5f47862cd1ff6733`](https://sepolia.basescan.org/address/0xe2659dc0d716B1226DF6a09A5f47862cd1ff6733) | ✅ Active |

#### Designated Address Conditions

For arbiter, service provider, DAO, platform, or any designated address access control:

| Contract | Notes |
|----------|-------|
| **StaticAddressCondition** | Deploy per use case - Generic designated address condition for arbiter, service provider, DAO multisig, platform treasury, etc. |

**USDC (Base Sepolia):** [`0x036CbD53842c5426634e7929541eC2318f3dCF7e`](https://sepolia.basescan.org/address/0x036CbD53842c5426634e7929541eC2318f3dCF7e)

### Project Contracts

This repository contains contracts for the x402r refund extension system.

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERACTIONS                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Payer              Receiver              Designated Address                │
│    │                   │                         │                           │
│    │  authorize()      │  release()              │  refund*() (if configured)│
│    │  freeze()         │  charge()               │  updateStatus()           │
│    │  requestRefund()  │  requestRefund()        │  release() (if configured)│
└────┼───────────────────┼─────────────────────────┼───────────────────────────┘
     │                   │                         │
     ▼                   ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PAYMENT OPERATOR                                    │
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
│  Example: Release requires (Receiver OR DesignatedAddr) AND EscrowPassed│
│                                                                   │
│  OrCondition([                                                   │
│    ReceiverCondition,                                            │
│    StaticAddressCondition(designatedAddr)                        │
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
│ PaymentOperatorFactory  │◄─── Owner (Multisig in production)
└────────────┬────────────┘
             │ deploys
             ▼
┌─────────────────────────┐      ┌─────────────────────────┐
│   PaymentOperator       │─────►│    AuthCaptureEscrow    │
│  (per-config instance)  │      │   (shared singleton)    │
└────────────┬────────────┘      └─────────────────────────┘
             │ uses
             ▼
┌─────────────────────────────────────────────────────────────┐
│                    PLUGGABLE CONDITIONS                      │
├─────────────────────────────────────────────────────────────┤
│  Access Conditions:          │  Time Conditions:            │
│  - PayerCondition            │  - EscrowPeriodCondition     │
│  - ReceiverCondition         │    └─► EscrowPeriodRecorder  │
│  - StaticAddressCondition    │        └─► FreezePolicy      │
│  - AlwaysTrueCondition       │                              │
├─────────────────────────────────────────────────────────────┤
│  Combinators:                │  Auxiliary:                  │
│  - AndCondition              │  - RefundRequest             │
│  - OrCondition               │  - FreezePolicyFactory       │
│  - NotCondition              │                              │
└─────────────────────────────────────────────────────────────┘
```

### Roles & Permissions

| Role | Capabilities |
|------|-------------|
| **Payer** | `authorize()`, `freeze()`, `unfreeze()`, `requestRefund()`, `cancelRefundRequest()`, `void()` (after expiry) |
| **Receiver** | `release()` (if condition allows), `charge()` |
| **Designated Address** | Per operator configuration - can include `refundInEscrow()`, `refundPostEscrow()`, `release()`, `updateStatus()` (arbiter, service provider, DAO, etc.) |
| **Owner** | `queueFeesEnabled()`, `executeFeesEnabled()`, `cancelFeesEnabled()`, `rescueETH()` |

**Authorization Expiry:** The `PaymentInfo` struct includes an `authorizationExpiry` field from base commerce-payments. Payers can set this to limit how long receivers can charge funds. Set to `type(uint48).max` for no expiry, or specify a timestamp for time-limited authorizations (useful for subscriptions). After expiry, payers can reclaim unused funds via `void()`.

### Security Features

| Feature | Implementation |
|---------|---------------|
| **Reentrancy Protection** | `ReentrancyGuardTransient` on escrow |
| **CEI Pattern** | All functions: Checks → Effects → Interactions |
| **2-Step Ownership** | Solady's `requestOwnershipHandover()` + `completeOwnershipHandover()` |
| **24h Timelock** | Fee changes require queue → wait → execute |
| **Multisig Requirement** | Owner must be Gnosis Safe in production |
| **Incident Response** | See [SECURITY.md](SECURITY.md) |

---

## ⛽ Gas Benchmarks

Typical gas costs for common operations (measured with via-IR optimization and reentrancy protection):

### Core Operations

| Operation | Gas Cost | Previous | Savings | Notes |
|-----------|----------|----------|---------|-------|
| **Payment Authorization (First)** | ~404,000 | ~473,000 | **-69k (-14.6%)** | First payment to/from address (new storage slots) |
| **Payment Authorization (Subsequent)** | ~287,000 | ~473,000 | **-186k (-39.3%)** | Additional payments (existing storage) |
| **Payment Release** | ~552,000 | ~552,000 | 0 | Release after escrow period with fee distribution |
| **Refund Request** | ~591,000 | ~591,000 | 0 | Create refund request with tracking |
| **Refund Approval** | ~677,000 | ~677,000 | 0 | Complete refund workflow (includes escrow call) |
| **Cancel Refund** | ~617,000 | ~617,000 | 0 | Cancel pending refund request |
| **Freeze Payment** | ~486,000 | ~486,000 | 0 | Payer freezes payment during escrow |

**Implementation**: Uses mapping + counter pattern for efficient payment indexing (22k gas first write, 5k subsequent).

### Condition Evaluation

| Conditions | Gas Cost | Scaling |
|------------|----------|---------|
| 1 condition | ~50,000 | Single check |
| 2 conditions (AND) | ~75,000 | Linear |
| 5 conditions (AND) | ~150,000 | Linear |
| 10 conditions (MAX) | ~479,000 | Near-linear |

**Recommended Complexity**: Keep combinator depth ≤ 5 for optimal gas efficiency.

### Token Rejection (Safety)

| Test | Gas Cost | Result |
|------|----------|--------|
| Fee-on-transfer detection | ~473,000 | ✅ Rejects (strict balance check) |
| Rebasing token detection | ~485,000 | ✅ Detects accounting mismatch |
| Standard ERC20 | ~473,000 | ✅ Accepts |

**Token Safety**: Protocol intentionally rejects fee-on-transfer and rebasing tokens to prevent accounting errors. See [TOKENS.md](TOKENS.md) for details.

### Gas Optimization

**Already Implemented**:
- ✅ Solady library (assembly-optimized)
- ✅ Via-IR compilation
- ✅ ReentrancyGuardTransient (transient storage, EIP-1153)
- ✅ Immutable variables
- ✅ Packed storage layout
- ✅ Custom errors

**Status**: Gas costs are **excellent** for the security features provided. See [GAS_OPTIMIZATION_REPORT.md](GAS_OPTIMIZATION_REPORT.md) for detailed analysis.

### Network Cost Estimates

Estimated transaction costs on different networks (at typical gas prices):

| Network | Gas Price | Authorization (First) | Authorization (Subsequent) | Release | Refund |
|---------|-----------|----------------------|---------------------------|---------|--------|
| **Base Mainnet** | 0.001 gwei | ~$0.0004 | ~$0.0003 | ~$0.0006 | ~$0.0007 |
| **Base Sepolia** | Free | Free | Free | Free | Free |
| **Ethereum L1** | 30 gwei | ~$12.12 | ~$8.61 | ~$16.56 | ~$20.31 |

**Recommendation**: Deploy on Base for low-cost transactions (100-1000x cheaper than Ethereum L1).

### Comparison with Alternatives

| Protocol | Authorization | Release | Notes |
|----------|--------------|---------|-------|
| **x402r** | 287-404k | 552k | Optimized indexing + reentrancy protection + flexible conditions |
| Gnosis Safe | ~300k | ~250k | Multi-sig overhead, less flexible |
| Uniswap Permit2 | ~150k | ~100k | Signature-based, no escrow |
| Superfluid | ~400k | Streaming | Continuous flow, different model |

**Trade-off**: Competitive gas costs with significantly better security and flexibility ✓

### Pagination Queries (On-Chain)

| Query Type | Gas Cost | Notes |
|------------|----------|-------|
| **Get 10 payments** | ~8,000 | Paginated query (offset + count) |
| **Get 50 payments** | ~32,000 | Scales linearly with count |
| **Get single payment** | ~1,300 | Direct index access |

**API**: `getPayerPayments(address, offset, count)` returns paginated results
- No need for external indexers (The Graph)
- Fully on-chain, decentralized
- Bounded gas cost (never unbounded array returns)

### Gas Monitoring

Gas costs are continuously monitored in CI/CD:
- **Baseline**: Updated on every merge to `main`
- **Regression Detection**: PRs fail if gas increases > 5%
- **Nightly Benchmarks**: Tracked in `.gas-snapshot`

See [CI_CD_GUIDE.md](CI_CD_GUIDE.md) for details.

---

#### Commerce Payments Contracts

The commerce-payments contracts provide refund functionality for Base Commerce Payments authorizations:

- **PaymentOperator**: `src/commerce-payments/operator/arbitration/PaymentOperator.sol`
  - Generic operator contract with pluggable conditions for flexible authorization logic. Supports marketplace, subscriptions, streaming, DAO governance, and custom payment flows.

- **RefundRequest**: `src/commerce-payments/requests/refund/RefundRequest.sol`
  - Contract for managing refund requests for Base Commerce Payments authorizations. Users can create refund requests, cancel their own pending requests, and merchants or arbiters can approve or deny them based on capture status.

#### Freeze Policy Options

The `EscrowPeriodRecorder` contract supports an optional freeze policy via the `FREEZE_POLICY` parameter. This determines who can freeze/unfreeze payments during the escrow period.

**FreezePolicy** uses `ICondition` contracts for authorization:

| Condition | Description |
|-----------|-------------|
| `PayerCondition` | Allows the payment's payer |
| `ReceiverCondition` | Allows the payment's receiver |
| `StaticAddressCondition(addr)` | Allows a designated address (arbiter, service provider, DAO, platform, etc.) |
| `AlwaysTrueCondition` | Allows anyone |

**Example:**

```solidity
// Payer freeze/unfreeze, 3-day duration
freezePolicyFactory.deploy(payerCondition, payerCondition, 3 days);

// Payer freeze, Designated Address unfreeze, permanent
address designatedAddrCondition = address(new StaticAddressCondition(designatedAddress));
freezePolicyFactory.deploy(payerCondition, designatedAddrCondition, 0);

// Anyone freeze, Receiver unfreeze, 7 days
freezePolicyFactory.deploy(alwaysTrueCondition, receiverCondition, 7 days);
```

**Note:** If `FREEZE_POLICY` is `address(0)` when deploying EscrowPeriodRecorder, freeze/unfreeze calls will revert with `NoFreezePolicy()` error.

#### PaymentOperatorFactory API

The `PaymentOperatorFactory` provides a single generic `deployOperator(OperatorConfig)` method. There are no convenience methods - users must construct the full `OperatorConfig` struct:

```solidity
struct OperatorConfig {
    address feeRecipient;
    address authorizeCondition;
    address authorizeRecorder;
    address chargeCondition;
    address chargeRecorder;
    address releaseCondition;
    address releaseRecorder;
    address refundInEscrowCondition;
    address refundInEscrowRecorder;
    address refundPostEscrowCondition;
    address refundPostEscrowRecorder;
    uint16 maxFeeBps;
    uint8 protocolFeePct;
}
```

**Example: Deploy a marketplace operator with arbiter**
```solidity
address arbiterCondition = address(new StaticAddressCondition(arbiterAddress));

PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
    feeRecipient: arbiterAddress,           // Arbiter earns fees for dispute resolution
    authorizeCondition: address(0),         // Anyone can authorize
    authorizeRecorder: address(0),          // No recording
    chargeCondition: RECEIVER_CONDITION,    // Only receiver can charge
    chargeRecorder: address(0),
    releaseCondition: address(0),           // Anyone can release after escrow
    releaseRecorder: escrowRecorder,        // Record timestamp
    refundInEscrowCondition: arbiterCondition,  // Only arbiter can refund
    refundInEscrowRecorder: address(0),
    refundPostEscrowCondition: arbiterCondition, // Only arbiter for post-escrow refunds
    refundPostEscrowRecorder: address(0),
    maxFeeBps: 5,                           // 0.05% fee
    protocolFeePct: 25                      // 25% to protocol
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
