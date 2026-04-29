# Contract Deployment

Deploy x402r smart contracts to EVM networks via a single CREATE2 canonical-deploy script.

---

## Overview

x402r uses **deterministic CREATE2 deployment via CreateX guarded salts**. Same deployer EOA + same byte-identical initCode = same address on every chain. The deploy script lives at `script/DeployCreate2.s.sol` and covers every canonical contract in one run.

> **Note:** New to x402r contracts? Start with [README.md](../README.md) to understand the architecture and plugin model.

> **Warning:** Contracts are currently **UNAUDITED**. Use at your own risk. `CANONICAL_OWNER` MUST be a multisig wallet (e.g., Gnosis Safe) in production.

## Prerequisites

Before deploying, ensure you have:
- **Foundry** installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- **Private key** for the deployer EOA (must be the same EOA on every chain — its address is encoded into the CreateX guarded salt)
- **CreateX** deployed at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` on the target chain (it's deployed on most major chains; verify before running)
- **Block explorer API key** for verification (optional but recommended)
- **Multisig wallet** address for `CANONICAL_OWNER`
- **Protocol fee recipient** address for `CANONICAL_FEE_RECIPIENT`

## Setup Environment

1. Clone the contracts repository:

```bash
cd x402r-contracts
```

2. Edit `script/DeployCreate2.s.sol` and set the canonical EOAs (these are pinned constants, not env vars — any drift moves the canonical addresses, so they're locked in source):

```solidity
address constant CANONICAL_OWNER = 0x...;          // Production multisig
address constant CANONICAL_FEE_RECIPIENT = 0x...;  // Production fee recipient
```

The script `require()`s both at runtime, so a missed update fails loudly.

3. Set the deployer key:

```bash
export PRIVATE_KEY=0x...
```

## Deploy

Use the `make deploy` target:

```bash
RPC_URL=https://sepolia.base.org make deploy
```

Or invoke `forge script` directly:

```bash
forge script script/DeployCreate2.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --slow \
  -vvv
```

This deploys, in order:

1. **commerce-payments primitives** (vendored from upstream `base/commerce-payments`, salt namespace `commerce-payments::v1::*`):
   - `AuthCaptureEscrow`
   - `ERC3009PaymentCollector`
   - `Permit2PaymentCollector`
2. **x402r-authored protocol** (salt namespace `x402r-canonical-v1::*`):
   - `ProtocolFeeConfig` (initial calculator = `address(0)`; owner sets via 7-day timelock per chain)
   - `PaymentOperatorFactory`
3. **Plugin singletons** (no ctor args):
   - `PayerCondition`, `ReceiverCondition`, `AlwaysTrueCondition`
4. **Plugin factories**:
   - `SignatureConditionFactory`, `StaticAddressConditionFactory`
   - `AndConditionFactory`, `OrConditionFactory`, `NotConditionFactory`
   - `HookCombinatorFactory`, `StaticFeeCalculatorFactory`
5. **Per-payment factories** (escrow-bound):
   - `EscrowPeriodFactory`, `FreezeFactory`
6. **Refund-side**:
   - `RefundRequestFactory`, `ReceiverRefundCollector`, `RefundRequestEvidenceFactory`

## Verify Deployment

### Check deployed addresses

The script logs every address it deploys. Save the output to a manifest file (a per-chain manifest matching the expected addresses is the recommended workflow).

Deployment addresses are also saved by Foundry in:
```
broadcast/DeployCreate2.s.sol/<chain-id>/run-latest.json
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

- [ ] `CANONICAL_OWNER` is a multisig wallet (Gnosis Safe) — pinned in `DeployCreate2.s.sol`
- [ ] `CANONICAL_FEE_RECIPIENT` is configured — pinned in `DeployCreate2.s.sol`
- [ ] Deployer EOA is the same one used on previous chains (CreateX guarded salts encode it)
- [ ] CreateX is deployed on the target chain
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
- Different library / submodule commits
- `bytecode_hash` not stripped (must be `bytecode_hash = "none"` in `foundry.toml`)
- Different deployer EOA (CreateX guarded salts encode the deployer; only the same EOA can use them)

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
