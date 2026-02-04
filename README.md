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
| **[AUDIT_PREP.md](docs/AUDIT_PREP.md)** | 📦 Complete audit preparation package (beta release) |
| **[AUDIT.md](docs/AUDIT.md)** | 📋 Comprehensive audit documentation |
| [SECURITY.md](docs/SECURITY.md) | 🔒 Security overview and threat model |
| [OPERATOR_SECURITY.md](docs/OPERATOR_SECURITY.md) | 🛡️ Operator-specific security considerations |
| [TOKENS.md](docs/TOKENS.md) | 🪙 Token compatibility and handling |
| [FUZZING.md](docs/FUZZING.md) | 🔬 Fuzzing methodology and invariants |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | 🚀 Contract deployment guide |
| [DEPLOYMENT_CHECKLIST.md](docs/DEPLOYMENT_CHECKLIST.md) | ✅ Production deployment checklist |
| [MONITORING.md](docs/MONITORING.md) | 📈 Event monitoring and indexing |
| [GAS_BREAKDOWN.md](docs/GAS_BREAKDOWN.md) | 📊 Detailed gas cost analysis |

## Quick Start

```shell
# Clone and build
git clone --recursive https://github.com/x402r/x402r-contracts.git
cd x402r-contracts
forge build

# Run tests
forge test

# Check formatting
forge fmt --check
```

### Deploy a Payment Operator (Local)

```solidity
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ProtocolFeeConfig} from "src/plugins/fees/ProtocolFeeConfig.sol";
import {PaymentOperatorFactory} from "src/operator/PaymentOperatorFactory.sol";
import {PaymentOperator} from "src/operator/payment/PaymentOperator.sol";

// 1. Deploy infrastructure
AuthCaptureEscrow escrow = new AuthCaptureEscrow();
ProtocolFeeConfig feeConfig = new ProtocolFeeConfig(address(0), feeRecipient, owner);
PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(feeConfig));

// 2. Configure and deploy operator
PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
    feeRecipient: feeRecipient,
    feeCalculator: address(0),            // No operator fee
    authorizeCondition: address(0),        // Anyone can authorize
    authorizeRecorder: address(0),         // No recording
    chargeCondition: address(0),
    chargeRecorder: address(0),
    releaseCondition: address(0),          // Anyone can release
    releaseRecorder: address(0),
    refundInEscrowCondition: address(0),
    refundInEscrowRecorder: address(0),
    refundPostEscrowCondition: address(0),
    refundPostEscrowRecorder: address(0)
});
address operator = factory.deployOperator(config);

// 3. Use the operator
PaymentOperator op = PaymentOperator(operator);
op.authorize(paymentInfo, amount, tokenCollector, "");
op.release(paymentInfo, amount);
```

---

### Deployed Addresses

**Source of truth:** [`@x402r/sdk`](https://github.com/BackTrackCo/x402r-sdk/blob/main/packages/core/src/config/index.ts)

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
│  Owner Functions (7-day Timelock):  │                                        │
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
│           EscrowPeriod                                           │
│         ])                                                       │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Escrow Period & Freeze Flow

Freeze and EscrowPeriod are now **separate, composable modules**:

- **EscrowPeriod**: ICondition that blocks release during the escrow period
- **Freeze**: Standalone ICondition with `freeze()`/`unfreeze()` methods

Compose them via `AndCondition([escrowPeriod, freeze])` when you want both behaviors.

```
Timeline:
├─────────────── ESCROW_PERIOD (e.g., 7 days) ───────────────┼──── Post-Escrow ────►
│                                                             │
│  [Payer can freeze via Freeze contract]                    │  [Release allowed]
│  [Release blocked by EscrowPeriod]                         │  [Freeze blocked]
│                                                             │
│  Freeze.freeze() ──► PaymentFrozen                         │
│  Freeze.unfreeze() ──► PaymentUnfrozen                     │
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
│  Access Conditions:          │  Time/State Conditions:      │
│  - PayerCondition            │  - EscrowPeriod              │
│  - ReceiverCondition         │  - Freeze                    │
│  - StaticAddressCondition    │    └─► FreezePolicy          │
│  - AlwaysTrueCondition       │                              │
├─────────────────────────────────────────────────────────────┤
│  Combinators:                │  Recorders (Optional):       │
│  - AndCondition              │  - PaymentIndexRecorder      │
│  - OrCondition               │  - RecorderCombinator        │
│  - NotCondition              │                              │
├─────────────────────────────────────────────────────────────┤
│  Auxiliary:                  │                              │
│  - RefundRequest             │                              │
│  - FreezePolicyFactory       │                              │
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
| **7-day Timelock** | Fee changes require queue → wait → execute |
| **Multisig Requirement** | Owner must be Gnosis Safe in production |
| **Incident Response** | See [SECURITY.md](SECURITY.md) |

---

## ⛽ Gas Benchmarks

Typical gas costs for common operations (measured with via-IR optimization and reentrancy protection):

### Core Operations

| Operation | Gas Cost | With Indexing | Notes |
|-----------|----------|---------------|-------|
| **Payment Authorization** | ~231,000 | ~273,000 | Minimal storage (fees only) |
| **Payment Release** | ~65,000 | ~65,000 | Release after escrow period |
| **Direct Charge** | ~285,000 | ~327,000 | Immediate capture (no escrow) |
| **Refund In Escrow** | ~45,000 | ~45,000 | Refund before release |
| **Freeze Payment** | ~50,000 | ~50,000 | Payer freezes during escrow |

**Implementation**: Payment indexing is **optional** via `PaymentIndexRecorder`. Deploy with indexing for on-chain queries (+42k gas first, +22k subsequent) or skip for gas savings when using external indexers (The Graph).

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

| Network | Gas Price | Authorization | Release | Charge |
|---------|-----------|---------------|---------|--------|
| **Base Mainnet** | 0.001 gwei | ~$0.0002 | ~$0.0001 | ~$0.0003 |
| **Base Sepolia** | Free | Free | Free | Free |
| **Ethereum L1** | 30 gwei | ~$6.93 | ~$1.95 | ~$8.55 |

**Recommendation**: Deploy on Base for low-cost transactions (100-1000x cheaper than Ethereum L1).

### Comparison with Alternatives

| Protocol | Authorization | Release | Notes |
|----------|--------------|---------|-------|
| **x402r** | ~231k | ~65k | Minimal storage + reentrancy protection + flexible conditions |
| Gnosis Safe | ~300k | ~250k | Multi-sig overhead, less flexible |
| Uniswap Permit2 | ~150k | ~100k | Signature-based, no escrow |
| Superfluid | ~400k | Streaming | Continuous flow, different model |

**Trade-off**: Competitive gas costs with significantly better security and flexibility ✓

### Pagination Queries (On-Chain)

**Optional Feature**: Deploy `PaymentIndexRecorder` to enable on-chain payment lookups.

| Query Type | Gas Cost | Notes |
|------------|----------|-------|
| **Get 10 payments** | ~20,000 | Paginated query (hash + amount) |
| **Get 50 payments** | ~82,000 | Scales linearly with count |
| **Get single payment** | ~2,000 | Direct index access |

**API**: `PaymentIndexRecorder.getPayerPayments(address, offset, count)` returns `(bytes32[] hashes, uint256 total)`:
- `hashes`: Array of payment hashes for escrow lookup
- `total`: Total number of payments for this address

**Note**: For timestamps, use `EscrowPeriod` which tracks authorization times. For amounts, query the escrow's `paymentState(hash).capturableAmount`.
- **With indexing**: On-chain queries available, no external indexer needed
- **Without indexing**: Use external indexer (The Graph) for lower gas costs
- Fully on-chain, decentralized when enabled
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

#### Arbiter Registry

The `ArbiterRegistry` provides on-chain discovery of arbiters for dispute resolution:

```solidity
// Self-register as an arbiter
arbiterRegistry.register("https://arbiter.example.com/api/disputes");

// Update your URI
arbiterRegistry.updateUri("https://new-api.example.com/disputes");

// Deregister
arbiterRegistry.deregister();

// Query arbiters
string memory uri = arbiterRegistry.getUri(arbiterAddress);
bool registered = arbiterRegistry.isRegistered(arbiterAddress);
uint256 count = arbiterRegistry.arbiterCount();

// Paginated listing
(address[] memory arbiters, string[] memory uris, uint256 total) =
    arbiterRegistry.getArbiters(0, 10);
```

**URI Format**: The URI can point to:
- REST API endpoint: `https://arbiter.example.com/api/disputes`
- IPFS metadata: `ipfs://QmXxx...`
- Any URL with arbiter information (contact, terms, pricing)

**Events:**
- `ArbiterRegistered(address indexed arbiter, string uri)`
- `ArbiterUriUpdated(address indexed arbiter, string oldUri, string newUri)`
- `ArbiterDeregistered(address indexed arbiter)`

#### Freeze Module

**Freeze** is a standalone `ICondition` contract with `freeze()`/`unfreeze()` methods. It's now separate from `EscrowPeriod` for better composability.

**Deploy via FreezeFactory:**

```solidity
// Deploy Freeze with FreezePolicy and optional EscrowPeriod constraint
address freeze = freezeFactory.deploy(freezePolicy, escrowPeriodContract);

// escrowPeriodContract = address(0) means freeze is unconstrained by time
// escrowPeriodContract = EscrowPeriod address means freeze only works during escrow period
```

**FreezePolicy** determines who can freeze/unfreeze using `ICondition` contracts:

| Condition | Description |
|-----------|-------------|
| `PayerCondition` | Allows the payment's payer |
| `ReceiverCondition` | Allows the payment's receiver |
| `StaticAddressCondition(addr)` | Allows a designated address (arbiter, service provider, DAO, platform, etc.) |
| `AlwaysTrueCondition` | Allows anyone |

**Example:**

```solidity
// 1. Deploy FreezePolicy (payer freeze/unfreeze, 3-day duration)
address freezePolicy = freezePolicyFactory.deploy(payerCondition, payerCondition, 3 days);

// 2. Deploy EscrowPeriod (7 days, operator-only recording)
address escrowPeriod = escrowPeriodFactory.deploy(7 days, bytes32(0));

// 3. Deploy Freeze (constrained to escrow period)
address freeze = freezeFactory.deploy(freezePolicy, escrowPeriod);

// 4. Compose for release condition: must pass both escrow period AND not be frozen
address releaseCondition = address(new AndCondition([ICondition(escrowPeriod), ICondition(freeze)]));
```

**Composition Patterns:**
- Escrow period only: `releaseCondition = escrowPeriod`
- Freeze only: `releaseCondition = freeze`
- Both: `releaseCondition = AndCondition([escrowPeriod, freeze])`

#### PaymentOperatorFactory API

The `PaymentOperatorFactory` provides a single generic `deployOperator(OperatorConfig)` method. There are no convenience methods - users must construct the full `OperatorConfig` struct:

```solidity
struct OperatorConfig {
    address feeRecipient;
    address feeCalculator;
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
}
```

**Example: Deploy a marketplace operator with arbiter**
```solidity
// Deploy arbiter condition via factory (deterministic address, idempotent)
address arbiterCondition = staticAddressConditionFactory.deploy(arbiterAddress);

PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
    feeRecipient: arbiterAddress,           // Arbiter earns fees for dispute resolution
    feeCalculator: address(feeCalc),        // Operator fee calculator
    authorizeCondition: address(0),         // Anyone can authorize
    authorizeRecorder: address(0),          // No recording
    chargeCondition: RECEIVER_CONDITION,    // Only receiver can charge
    chargeRecorder: address(0),
    releaseCondition: address(0),           // Anyone can release after escrow
    releaseRecorder: escrowRecorder,        // Record timestamp
    refundInEscrowCondition: arbiterCondition,  // Only arbiter can refund
    refundInEscrowRecorder: address(0),
    refundPostEscrowCondition: arbiterCondition, // Only arbiter for post-escrow refunds
    refundPostEscrowRecorder: address(0)
});
address operator = factory.deployOperator(config);
```

**Note:** `address(0)` for a condition means "allow all" (no restriction). `address(0)` for a recorder means "no-op" (no state recording).

#### Optional Payment Indexing

`PaymentIndexRecorder` provides on-chain payment lookups by payer/receiver. Deploy once and share across operators:

```solidity
// Deploy indexer (optional)
PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow));

// Option 1: Enable indexing
PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
    // ...
    authorizeRecorder: address(indexRecorder),  // Index on authorize
    chargeRecorder: address(indexRecorder),     // Index on charge
    // ...
});

// Option 2: Skip indexing (lower gas, use The Graph instead)
PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
    // ...
    authorizeRecorder: address(0),  // No indexing
    chargeRecorder: address(0),     // No indexing
    // ...
});

// Query payments (requires indexing enabled)
(bytes32[] memory hashes, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 10);
// hashes[0] - Payment hash for escrow lookup
// For amounts: escrow.paymentState(hashes[0]).capturableAmount
// For timestamps: use EscrowPeriod.authorizationTimes(hash)
```

**Benefits:**
- **Efficient Storage**: Stores only payment hashes (minimal gas cost)
- **Gas Savings**: ~55k per authorization when indexing disabled
- **Flexibility**: Deploy with or without on-chain queries
- **Composability**: Combine with other recorders via `RecorderCombinator`
- **No Duplication**: Use `EscrowPeriod` for timestamps, escrow for amounts

**When to use indexing:**
- ✅ Need on-chain payment history queries
- ✅ Building fully decentralized applications
- ✅ Want to avoid external dependencies

**When to skip indexing:**
- ✅ Using external indexer (The Graph, Dune)
- ✅ Optimizing for minimum gas costs
- ✅ Don't need on-chain payment history

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
