# Contract Deployment

Deploy x402r smart contracts to EVM networks via a single CREATE2 canonical-deploy script bound to the canonical Base `AuthCaptureEscrow`.

---

## Overview

x402r uses **deterministic CREATE2 deployment via CreateX permissionless salts**. Same salt + byte-identical initCode = same address on every chain, regardless of who broadcasts.

The upstream `base/commerce-payments@v1.0.0` primitives (`AuthCaptureEscrow`, `ERC3009PaymentCollector`, `Permit2PaymentCollector`) are deployed by Base at canonical addresses on Base mainnet (8453) and Base Sepolia (84532); see the [upstream README](https://github.com/base/commerce-payments) for those addresses. x402r does not redeploy them — `DeployX402r.s.sol` reads the escrow from the hardcoded `BASE_AUTH_CAPTURE_ESCROW` constant and asserts the address has code on the target chain before broadcasting.

| Script | Contracts |
|---|---|
| `script/DeployX402r.s.sol` | Operator factory, plugins, refund-side, hook singletons (BUSL-1.1, x402r-authored) |
| `script/PredictAddresses.s.sol` | _(read-only)_ |

Salt namespaces:
- `x402r-canonical-v1::*` — escrow-independent contracts (`ProtocolFeeConfig`, condition singletons, ctor-arg-free factories, `RefundRequestEvidenceFactory`). Already live on the chains in `deployments/canonical.json`.
- `x402r-canonical-v1.0.1::*` — escrow-dependent contracts (`PaymentOperatorFactory`, `EscrowPeriodFactory`, `FreezeFactory`, `RefundRequestFactory`, `ReceiverRefundCollector`, `PaymentIndexRecorderHook`). Same source as v1, rebound to the canonical Base escrow. Bringing up v1.0.1 requires the canonical Base escrow on the chain — today, Base mainnet + Base Sepolia.

This matches the convention used by Permit2, UniversalRouter, Seaport, EntryPoint, and upstream `base/commerce-payments`: anyone with the source can verify and reproduce the deployment. The trust root is bytecode reproducibility — anyone deploying the exact x402r bytecode at the canonical salt is, by definition, deploying x402r.

> **Note:** New to x402r contracts? Start with [README.md](../README.md) to understand the architecture and plugin model.

> **Warning:** Contracts are currently **UNAUDITED**. Use at your own risk. `CANONICAL_OWNER` MUST be a multisig wallet (e.g., Gnosis Safe) in production.

## Prerequisites

Before deploying, ensure you have:
- **Foundry** installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- **Private key** for a deployer EOA with gas on the target chain. The salt is permissionless, so the deployer's identity does not affect the resulting address — but you should still treat the canonical deploy as a one-time event per chain to avoid duplicates.
- **CreateX** deployed at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` on the target chain
- **Canonical Base AuthCaptureEscrow** deployed at `0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff` on the target chain (today: Base mainnet + Base Sepolia). The deploy script reverts pre-broadcast if the address has no code.
- **Block explorer API key** for verification (optional but recommended)
- **Multisig wallet** address for `OWNER_ADDRESS`
- **Protocol fee recipient** address for `PROTOCOL_FEE_RECIPIENT`

## Setup Environment

1. Clone the contracts repository:

```bash
cd x402r-contracts
```

2. Set the deployer key and canonical EOAs:

```bash
export PRIVATE_KEY=0x...
export OWNER_ADDRESS=0x...           # Production multisig (Gnosis Safe)
export PROTOCOL_FEE_RECIPIENT=0x...  # Production fee recipient
```

`DeployX402r.s.sol` reads `OWNER_ADDRESS` and `PROTOCOL_FEE_RECIPIENT` from env and `require()`s both. They are baked immutably into `ProtocolFeeConfig`, and the script's fragmentation guard reverts if the predicted `ProtocolFeeConfig` address doesn't match `EXPECTED_PROTOCOL_FEE_CONFIG` (catches typos that would otherwise fragment from the canonical deployment).

## Deploy

### Step 1: Predict (always run first)

`make predict` (or `forge script script/PredictAddresses.s.sol -vvv`) prints every canonical address along with its `initCodeHash`. Run this on every developer machine that will broadcast a deploy. Predicted addresses must match across machines and against the manifest — divergence is the canary for toolchain drift, and stops the deploy before it lands at a non-canonical address.

### Step 2: Deploy x402r-authored contracts

```bash
RPC_URL=https://sepolia.base.org make deploy-x402r
```

The script asserts the canonical Base `AuthCaptureEscrow` has code on the target chain; if not, the canonical primitives are not yet deployed there and x402r v1.0.1 cannot bring up. Deploys, in order:

1. **Protocol infrastructure**:
   - `ProtocolFeeConfig` (salt `x402r-canonical-v1::*`; initial calculator = `address(0)`; owner sets via 7-day timelock per chain)
   - `PaymentOperatorFactory` (salt `x402r-canonical-v1.0.1::*`; escrow-bound)
2. **Plugin singletons** (salt `x402r-canonical-v1::*`, no ctor args):
   - `PayerCondition`, `ReceiverCondition`, `AlwaysTrueCondition`
3. **Plugin factories** (salt `x402r-canonical-v1::*`):
   - `SignatureConditionFactory`, `StaticAddressConditionFactory`
   - `AndConditionFactory`, `OrConditionFactory`, `NotConditionFactory`
   - `HookCombinatorFactory`, `StaticFeeCalculatorFactory`
4. **Per-payment factories** (salt `x402r-canonical-v1.0.1::*`, escrow-bound):
   - `EscrowPeriodFactory`, `FreezeFactory`
5. **Refund-side**:
   - `RefundRequestFactory` (v1.0.1, escrow-bound)
   - `ReceiverRefundCollector` (v1.0.1, escrow-bound)
   - `RefundRequestEvidenceFactory` (v1)
6. **Hook singletons**:
   - `PaymentIndexRecorderHook` (v1.0.1, escrow-bound)

Or invoke `forge script` directly:

```bash
forge script script/DeployX402r.s.sol --rpc-url $RPC_URL --broadcast --verify --slow -vvv
```

## Verify Deployment

### Check deployed addresses

The script logs every address it deploys. Save the output to a manifest file (a per-chain manifest matching the expected addresses is the recommended workflow).

Deployment addresses are also saved by Foundry in:
```
broadcast/DeployX402r.s.sol/<chain-id>/run-latest.json
```

### Cross-check that addresses match the manifest

A correctly-set-up CREATE2 deploy lands at exactly the same address on every chain. After running on chain N, the printed addresses should match the manifest entries. Any mismatch indicates compiler / library / salt drift — investigate before continuing to other chains.

### Verify contract state

```bash
# ProtocolFeeConfig owner (should be CANONICAL_OWNER)
cast call $PROTOCOL_FEE_CONFIG "owner()" --rpc-url $RPC_URL

# ProtocolFeeConfig fee recipient (should be CANONICAL_FEE_RECIPIENT)
cast call $PROTOCOL_FEE_CONFIG "protocolFeeRecipient()" --rpc-url $RPC_URL

# PaymentOperatorFactory escrow + protocolFeeConfig (constructor-pinned)
cast call $PAYMENT_OPERATOR_FACTORY "ESCROW()" --rpc-url $RPC_URL
cast call $PAYMENT_OPERATOR_FACTORY "PROTOCOL_FEE_CONFIG()" --rpc-url $RPC_URL
```

### Verify owner is multisig

```bash
make verify-owner OWNER_ADDRESS=$CANONICAL_OWNER RPC_URL=$RPC_URL
```

### Verify on block explorer

Contracts are auto-verified during deployment via `--verify`. Confirm at:
- **Base Mainnet**: https://basescan.org/address/YOUR_ADDRESS
- **Base Sepolia**: https://sepolia.basescan.org/address/YOUR_ADDRESS

## Deploy Operator Instances

After the canonical deploy, create operator instances via `PaymentOperatorFactory.deployOperator()`. The factory uses CREATE2 (per-config) so calling with the same config is idempotent — same config returns the existing operator instead of deploying a new one.

Each operator config picks plugin addresses for the 10 plugin slots (5 pre-action conditions + 5 post-action hooks) plus a fee receiver and an optional fee calculator. See README's "Plugin Architecture" section for a worked example.

## Supported Networks

Configure RPC endpoints in `foundry.toml` or use `--rpc-url`:

| Network | RPC URL | Chain ID |
|---------|---------|----------|
| Base Mainnet | https://mainnet.base.org | 8453 |
| Base Sepolia | https://sepolia.base.org | 84532 |
| Optimism | https://mainnet.optimism.io | 10 |
| Arbitrum | https://arb1.arbitrum.io/rpc | 42161 |

## Production Checklist

Before deploying to mainnet:

- [ ] `OWNER_ADDRESS` env var is a multisig wallet (Gnosis Safe)
- [ ] `PROTOCOL_FEE_RECIPIENT` env var is configured
- [ ] CreateX is deployed on the target chain
- [ ] Canonical Base `AuthCaptureEscrow` (`0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff`) has code on the target chain (`cast code` returns non-empty)
- [ ] Foundry submodule pin matches the manifest commit (lib/commerce-payments at v1.0.0)
- [ ] Foundry compiler config matches the manifest (solc, evm_version, optimizer_runs, bytecode_hash)
- [ ] Deployer account has sufficient gas tokens
- [ ] Block explorer API key is configured
- [ ] `make predict` output matches the manifest — addresses identical across machines
- [ ] All tests passing: `forge test`
- [ ] Monitoring systems ready (see [MONITORING.md](./MONITORING.md))

## Troubleshooting

### Deployment Fails with "Insufficient Funds"

Ensure deployer account has enough native tokens for gas:
```bash
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL
```

### Address mismatch between chains

CREATE2 addresses are sensitive to bytecode. Common causes:
- Different solc version (must match `foundry.toml` lock)
- Different optimizer settings (`optimizer_runs = 100000` is required)
- Different library / submodule commits (verify `lib/commerce-payments` is at the manifest commit)
- `bytecode_hash` not stripped (must be `bytecode_hash = "none"` in `foundry.toml`)

### Verification Fails

Manually verify contracts:
```bash
forge verify-contract $CONTRACT_ADDRESS \
  src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory \
  --chain-id 84532 \
  --watch
```

### RPC Timeout

Increase timeout in `foundry.toml`:
```toml
[rpc_endpoints]
timeout = 60000  # 60 seconds
```

---

## Related Documentation

- [README.md](../README.md) - Architecture and quick start
- [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) - Detailed production checklist
- [MONITORING.md](./MONITORING.md) - Set up monitoring for deployed contracts
- [SECURITY.md](./SECURITY.md) - Security considerations and incident response
