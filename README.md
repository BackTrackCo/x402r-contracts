## Deployed Contracts (Base Mainnet)

⚠️ **WARNING: CONTRACTS UNAUDITED - USE AT YOUR OWN RISK**

These contracts have been deployed to Base mainnet but have **not been audited**. 
Users should exercise extreme caution and conduct thorough due diligence before 
interacting with these contracts. The developers assume no liability for any 
losses incurred from using these contracts.

### Contract Addresses

**Source of truth:** This README. Addresses will eventually be moved to `@x402r/sdk` package.

| Contract | Address |
|----------|---------|
| Escrow | `0x6De78B73dE889BEda028C02ECb38247EBD7e350e` |
| MerchantRouter | `0xa48E8AdcA504D2f48e5AF6be49039354e922913F` |
| DepositRelayFactory | `0xb6D04024077bDfcfE3b62aF3d119bf44DBbfC41D` |
| DepositRelay (impl) | `0x3CEb7EE0309B47d127e644B47e1D2e1A4bAAfc4c` |
| RefundRequest | `0x55e0Fb85833f77A0d699346E827afa06bcf58e4e` |
| CreateX | `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Aave Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |

### Project Contracts

This repository contains contracts for the x402r refund extension system.

#### Commerce Payments Contracts

The commerce-payments contracts provide refund functionality for Base Commerce Payments authorizations:

- **ArbitrationOperator**: `src/commerce-payments/operator/ArbitrationOperator.sol`
  - Operator contract that wraps Base Commerce Payments and enforces refund delay for uncaptured funds, arbiter refund restrictions, and fee distribution.

- **RefundRequest**: `src/commerce-payments/requests/refund/RefundRequest.sol`
  - Contract for managing refund requests for Base Commerce Payments authorizations. Users can create refund requests, cancel their own pending requests, and merchants or arbiters can approve or deny them based on capture status.

#### Freeze Policy Options

The `EscrowPeriodCondition` contract supports an optional freeze policy via the `FREEZE_POLICY` parameter. This determines who can freeze/unfreeze payments during the escrow period:

**Options:**

1. **`address(0)` (No Freeze Policy)** - Default
   - Freeze/unfreeze functionality is disabled
   - Payments cannot be frozen once authorized
   - Use when freeze functionality is not needed

2. **`PayerFreezePolicy`** - Payer-only freeze
   - Only the payer can freeze/unfreeze their own payments
   - Deploy `PayerFreezePolicy` contract first, then use its address
   - Useful for buyer protection scenarios

3. **Custom `IFreezePolicy` Implementation**
   - Implement the `IFreezePolicy` interface with custom authorization logic
   - Can define any freeze/unfreeze rules (e.g., arbiter-only, multi-sig, time-based)
   - See `src/commerce-payments/release-conditions/escrow-period/types/IFreezePolicy.sol` for interface

**Example: Deploying with PayerFreezePolicy**

```bash
# 1. Deploy PayerFreezePolicy (or use existing)
forge script script/DeployPayerFreezePolicy.s.sol:DeployPayerFreezePolicy --rpc-url $RPC_URL --broadcast

# 2. Set FREEZE_POLICY to the deployed address
export FREEZE_POLICY=0x...

# 3. Deploy EscrowPeriodCondition with freeze policy
forge script script/DeployEscrowPeriodCondition.s.sol:DeployEscrowPeriodCondition --rpc-url $RPC_URL --broadcast
```

**Note:** If `FREEZE_POLICY` is not set or is `address(0)`, freeze/unfreeze calls will revert with `NoFreezePolicy()` error.

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
