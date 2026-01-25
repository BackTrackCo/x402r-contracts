## Deployed Contracts

⚠️ **WARNING: CONTRACTS UNAUDITED - USE AT YOUR OWN RISK**

These contracts have been deployed but have **not been audited**. 
Users should exercise extreme caution and conduct thorough due diligence before 
interacting with these contracts. The developers assume no liability for any 
losses incurred from using these contracts.

### Base Sepolia

**Source of truth:** This README. Addresses will eventually be moved to `@x402r/sdk` package.

| Contract | Address |
|----------|---------|
| AuthCaptureEscrow | `0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8` |
| ERC3009PaymentCollector | `0xed02d3E5167BCc9582D851885A89b050AB816a56` |
| EscrowPeriodConditionFactory | `0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178` |
| ArbitrationOperatorFactory | `0x46C44071BDf9753482400B76d88A5850318b776F` |
| PayerFreezePolicy | `0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316` |
| RefundRequest | `0x26A3d27139b442Be5ECc10c8608c494627B660BF` |

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
   - See `src/commerce-payments/conditions/escrow-period/types/IFreezePolicy.sol` for interface

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
