# Contract Deployment

Deploy x402r smart contracts to EVM networks via two CREATE2 canonical-deploy scripts, split by license.

---

## Overview

x402r uses **deterministic CREATE2 deployment via CreateX permissionless salts**. Same salt + byte-identical initCode = same address on every chain, regardless of who broadcasts. Deployment is split into two scripts to keep the licensing line clear:

| Script | Contracts | License of deployed contracts |
|---|---|---|
| `script/DeployCommercePayments.s.sol` | `AuthCaptureEscrow`, `ERC3009PaymentCollector`, `Permit2PaymentCollector` | MIT (vendored from `base/commerce-payments` at the `v1.0.0` tag) |
| `script/DeployX402r.s.sol` | Operator factory, plugins, refund-side | BUSL-1.1 (x402r-authored) |
| `script/PredictAddresses.s.sol` | _(read-only)_ | — |

This matches the convention used by Permit2, UniversalRouter, Seaport, EntryPoint, and upstream `base/commerce-payments`: anyone with the source can verify and reproduce the deployment. The trust root is bytecode reproducibility — anyone deploying the exact x402r bytecode at the canonical salt is, by definition, deploying x402r.

> **Note:** New to x402r contracts? Start with [README.md](../README.md) to understand the architecture and plugin model.

> **Warning:** Contracts are currently **UNAUDITED**. Use at your own risk. `CANONICAL_OWNER` MUST be a multisig wallet (e.g., Gnosis Safe) in production.

## Prerequisites

Before deploying, ensure you have:
- **Foundry** installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- **Private key** for a deployer EOA with gas on the target chain. The salt is permissionless, so the deployer's identity does not affect the resulting address — but you should still treat the canonical deploy as a one-time event per chain to avoid duplicates.
- **CreateX** deployed at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` on the target chain
- **Multicall3** at `0xcA11bde05977b3631167028862bE2a173976CA11` (used by `ERC3009PaymentCollector`)
- **Permit2** at `0x000000000022D473030F116dDEE9F6B43aC78BA3` (used by `Permit2PaymentCollector`)
- **Block explorer API key** for verification (optional but recommended)
- **Multisig wallet** address for `CANONICAL_OWNER` (x402r-side only)
- **Protocol fee recipient** address for `CANONICAL_FEE_RECIPIENT` (x402r-side only)

## Setup Environment

1. Clone the contracts repository:

```bash
cd x402r-contracts
```

2. Edit `script/DeployX402r.s.sol` and set the canonical EOAs (these are pinned constants, not env vars — any drift moves the canonical addresses, so they're locked in source):

```solidity
address constant CANONICAL_OWNER = 0x...;          // Production multisig
address constant CANONICAL_FEE_RECIPIENT = 0x...;  // Production fee recipient
```

The script `require()`s both at runtime, so a missed update fails loudly. (`DeployCommercePayments.s.sol` has no env-pinned constants.)

3. Set the deployer key:

```bash
export PRIVATE_KEY=0x...
```

## Deploy

### Step 1: Predict (always run first)

`make predict` (or `forge script script/PredictAddresses.s.sol -vvv`) prints every canonical address along with its `initCodeHash`. Run this on every developer machine that will broadcast a deploy. Predicted addresses must match across machines and against the manifest — divergence is the canary for toolchain drift, and stops the deploy before it lands at a non-canonical address.

### Step 2: Deploy MIT primitives

```bash
RPC_URL=https://sepolia.base.org make deploy-primitives
```

Deploys the upstream `base/commerce-payments` contracts (MIT), in order:

- `AuthCaptureEscrow`
- `ERC3009PaymentCollector(escrow, MULTICALL3)`
- `Permit2PaymentCollector(escrow, PERMIT2)`

Salt namespace `commerce-payments::v1::*`. Idempotent per chain — re-running on a chain where the contracts already exist will revert (CreateX rejects duplicate deploys at the same salt).

### Step 3: Deploy x402r-authored contracts

```bash
RPC_URL=https://sepolia.base.org make deploy-x402r
```

The script predicts the escrow address and asserts it has code; if not, run Step 2 first. Deploys, in order:

1. **Protocol infrastructure** (salt namespace `x402r-canonical-v1::*`):
   - `ProtocolFeeConfig` (initial calculator = `address(0)`; owner sets via 7-day timelock per chain)
   - `PaymentOperatorFactory`
2. **Plugin singletons** (no ctor args):
   - `PayerCondition`, `ReceiverCondition`, `AlwaysTrueCondition`
3. **Plugin factories**:
   - `SignatureConditionFactory`, `StaticAddressConditionFactory`
   - `AndConditionFactory`, `OrConditionFactory`, `NotConditionFactory`
   - `HookCombinatorFactory`, `StaticFeeCalculatorFactory`
4. **Per-payment factories** (escrow-bound):
   - `EscrowPeriodFactory`, `FreezeFactory`
5. **Refund-side**:
   - `RefundRequestFactory`, `ReceiverRefundCollector`, `RefundRequestEvidenceFactory`

Or invoke `forge script` directly for either:

```bash
forge script script/DeployCommercePayments.s.sol --rpc-url $RPC_URL --broadcast --verify --slow -vvv
forge script script/DeployX402r.s.sol           --rpc-url $RPC_URL --broadcast --verify --slow -vvv
```

## Verify Deployment

### Check deployed addresses

The script logs every address it deploys. Save the output to a manifest file (a per-chain manifest matching the expected addresses is the recommended workflow).

Deployment addresses are also saved by Foundry in:
```
broadcast/DeployCommercePayments.s.sol/<chain-id>/run-latest.json
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

- [ ] `CANONICAL_OWNER` is a multisig wallet (Gnosis Safe) — pinned in `DeployX402r.s.sol`
- [ ] `CANONICAL_FEE_RECIPIENT` is configured — pinned in `DeployX402r.s.sol`
- [ ] CreateX is deployed on the target chain
- [ ] Foundry submodule pin matches the manifest commit (lib/commerce-payments at v1.0.0)
- [ ] Foundry compiler config matches the manifest (solc, evm_version, optimizer_runs, bytecode_hash)
- [ ] Deployer account has sufficient gas tokens
- [ ] Block explorer API key is configured
- [ ] Deployment script tested on testnet — addresses match manifest
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
