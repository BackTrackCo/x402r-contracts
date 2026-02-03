# Contract Deployment

Deploy x402r smart contracts to EVM networks using Foundry deployment scripts.

---

## Overview

This guide covers deploying the x402r smart contract system to EVM-compatible networks. The deployment uses Foundry's script system and includes automated verification on block explorers.

> **Note:** New to x402r contracts? Start with [README.md](../README.md) to understand the architecture and factory patterns.

> **Warning:** Contracts are currently **UNAUDITED**. Use at your own risk. Owner addresses MUST be multisig wallets (e.g., Gnosis Safe) in production.

## Prerequisites

Before deploying, ensure you have:
- **Foundry** installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- **Private key** with sufficient native tokens for gas
- **Block explorer API key** (e.g., Basescan API key)
- **Multisig wallet** address for production owner
- **Protocol fee recipient** address

## Setup Environment

1. Clone the contracts repository:

```bash
cd x402r-contracts
```

2. Copy and configure environment variables:

```bash
cp .env.example .env
```

3. Edit `.env` with your configuration:

```bash
# Required
PRIVATE_KEY=0x...                           # Deployer account
ETHERSCAN_API_KEY=...                       # Basescan API key
PROTOCOL_FEE_RECIPIENT=0x...                # Fee recipient (immutable)
OWNER_ADDRESS=0x...                         # Factory owner (use multisig)

# Optional - defaults shown
MAX_TOTAL_FEE_RATE=5                        # 5 basis points (0.05%)
PROTOCOL_FEE_PERCENTAGE=25                  # 25% to protocol, 75% to arbiter
```

## Deployment Options

### Option 1: Deploy All Contracts (Recommended)

Deploy the complete system with one command:

```bash
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url base-sepolia \
  --broadcast \
  --verify \
  -vvvv
```

This deploys:
1. **AuthCaptureEscrow** - Escrow contract for holding funds
2. **ERC3009PaymentCollector** - Payment collector
3. **EscrowPeriodConditionFactory** - Factory for time-based conditions
4. **PaymentOperatorFactory** - Factory for operator instances
5. **Condition Singletons** - PayerCondition, ReceiverCondition, ArbiterCondition, AlwaysTrueCondition
6. **FreezePolicyFactory** - Factory for creating freeze policy instances
7. **RefundRequest** - Refund request manager

### Option 2: Deploy Individual Contracts

Deploy contracts separately for custom configurations:

#### Refund Request Singleton

```bash
forge script script/DeployRefundRequest.s.sol:DeployRefundRequest \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

#### Escrow Period Condition Factory

```bash
forge script script/DeployEscrowPeriodCondition.s.sol:DeployEscrowPeriodCondition \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

#### Freeze Policy Factory and Condition Singletons

Deploys FreezePolicyFactory and all condition singletons (PayerCondition, ReceiverCondition, ArbiterCondition, AlwaysTrueCondition):

```bash
forge script script/DeployFreezePolicyFactory.s.sol:DeployFreezePolicyFactory \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

These condition singletons can be used with the FreezePolicyFactory to create custom freeze policies.

## Verify Deployment

After deployment, verify contracts were deployed correctly:

### Check Deployed Addresses

Deployment addresses are saved in:
```
broadcast/DeployAll.s.sol/<chain-id>/run-latest.json
```

### Verify Contract State

```bash
# Check factory owner
cast call $FACTORY_ADDRESS "owner()" --rpc-url $RPC_URL

# Check protocol fee recipient
cast call $FACTORY_ADDRESS "protocolFeeRecipient()" --rpc-url $RPC_URL

# Check max fee rate
cast call $FACTORY_ADDRESS "maxTotalFeeRate()" --rpc-url $RPC_URL
```

### Verify on Block Explorer

Contracts are automatically verified during deployment. Confirm at:
- **Base Mainnet**: https://basescan.org/address/YOUR_ADDRESS
- **Base Sepolia**: https://sepolia.basescan.org/address/YOUR_ADDRESS

## Deploy Operator Instances

After deploying factories, create operator instances on-demand:

```bash
# Set environment variables
export ESCROW_ADDRESS=0x...
export ARBITER_ADDRESS=0x...

forge script script/DeployArbitrationOperator.s.sol:DeployArbitrationOperator \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

> **Tip:** The PaymentOperatorFactory uses CREATE2 for deterministic addresses. Calling with the same configuration returns the existing operator instead of deploying a new one.

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

- [ ] Owner address is a multisig wallet (Gnosis Safe)
- [ ] Protocol fee recipient is configured correctly
- [ ] Fee rates are appropriate for your use case
- [ ] Deployer account has sufficient gas tokens
- [ ] Block explorer API key is configured
- [ ] Deployment script tested on testnet
- [ ] All tests passing: `forge test`
- [ ] Monitoring systems ready (see [MONITORING.md](./MONITORING.md))

## Troubleshooting

### Deployment Fails with "Insufficient Funds"

Ensure deployer account has enough native tokens for gas:
```bash
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL
```

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
