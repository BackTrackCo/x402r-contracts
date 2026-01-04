## Deployed Contracts (Base Mainnet)

⚠️ **WARNING: CONTRACTS UNAUDITED - USE AT YOUR OWN RISK**

These contracts have been deployed to Base mainnet but have **not been audited**. 
Users should exercise extreme caution and conduct thorough due diligence before 
interacting with these contracts. The developers assume no liability for any 
losses incurred from using these contracts.

### CreateX
- **Address**: [`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`](https://basescan.org/address/0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed)
- **Contract**: `lib/createx/src/CreateX.sol:CreateX`
- **Description**: CREATE3 deployment contract used by the factory for deterministic address generation. This is the standard CreateX deployment for Base.

### Shared Escrow
- **Address**: [`0x6De78B73dE889BEda028C02ECb38247EBD7e350e`](https://basescan.org/address/0x6de78b73de889beda028c02ecb38247ebd7e350e)
- **Contract**: `src/simple/main/escrow/Escrow.sol:Escrow`
- **Description**: Shared escrow contract for refund extension. Merchants register with this escrow to enable deposits and refunds. Deployed with Aave Pool for yield generation. Includes `getDeposit()` function for querying deposit information. Supports full refunds only (partial refunds removed).

### DepositRelayFactory
- **Address**: [`0xb6D04024077bDfcfE3b62aF3d119bf44DBbfC41D`](https://basescan.org/address/0xb6d04024077bdfcfe3b62af3d119bf44dbbfc41d)
- **Contract**: `src/simple/main/x402/DepositRelayFactory.sol:DepositRelayFactory`
- **Description**: Factory contract that deploys DepositRelay proxies for merchants via CREATE3. Each merchant gets a deterministic proxy address. Uses the standard CreateX address. Deployed with Base Mainnet USDC address (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`).

### DepositRelay (Implementation)
- **Address**: [`0x3CEb7EE0309B47d127e644B47e1D2e1A4bAAfc4c`](https://basescan.org/address/0x3ceb7ee0309b47d127e644b47e1d2e1a4baafc4c)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`
- **Description**: Stateless implementation contract for deposit relays. Shared across all merchants via proxy pattern. Handles ERC3009 transfers signed for the relay proxy address and forwards tokens to the escrow.

### RefundRequest
- **Address**: [`0x55e0Fb85833f77A0d699346E827afa06bcf58e4e`](https://basescan.org/address/0x55e0fb85833f77a0d699346e827afa06bcf58e4e)
- **Contract**: `src/simple/main/requests/RefundRequest.sol:RefundRequest`
- **Description**: Contract for managing refund requests for escrow deposits. Users can create refund requests with IPFS links, cancel their own pending requests, and merchants or arbiters can approve or deny them. Tracks refund request status (Pending, Approved, Denied, Cancelled). Includes batch getters for efficient querying. Prevents denying refunds after they've been processed. Cancelled requests remain in indexing arrays for history tracking. Stores original deposit amount (`originalAmount`) when refund request is created, allowing display of refund amounts even after deposits are refunded.

### MerchantRegistrationRouter
- **Address**: [`0xa48E8AdcA504D2f48e5AF6be49039354e922913F`](https://basescan.org/address/0xa48e8adca504d2f48e5af6be49039354e922913f)
- **Contract**: `src/simple/main/x402/MerchantRegistrationRouter.sol:MerchantRegistrationRouter`
- **Description**: Router contract that atomically registers merchants with the escrow and deploys their relay proxy via the factory. Prevents frontrunning by combining both operations in a single transaction.

### Aave Pool (Production)
- **Address**: [`0xA238Dd80C259a72e81d7e4664a9801593F98d1c5`](https://basescan.org/address/0xa238dd80c259a72e81d7e4664a9801593f98d1c5)
- **Contract**: Aave V3 Pool
- **Description**: The Escrow contract uses Aave Pool directly (not ERC4626). Aave provides a secure, audited, and well-established lending protocol with strong security track record. The Escrow supplies USDC to Aave and receives aUSDC tokens, which accrue interest over time.

### Configuration
- **DEPOSIT_RELAY_FACTORY_ADDRESS**: `0xb6D04024077bDfcfE3b62aF3d119bf44DBbfC41D`
- **SHARED_ESCROW_ADDRESS**: `0x6De78B73dE889BEda028C02ECb38247EBD7e350e`
- **REFUND_REQUEST_ADDRESS**: `0x55e0Fb85833f77A0d699346E827afa06bcf58e4e`
- **MERCHANT_REGISTRATION_ROUTER_ADDRESS**: `0xa48E8AdcA504D2f48e5AF6be49039354e922913F`
- **DEPOSIT_RELAY_IMPLEMENTATION_ADDRESS**: `0x3CEb7EE0309B47d127e644B47e1D2e1A4bAAfc4c`
- **CREATEX_ADDRESS**: `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` (Standard CreateX deployment for Base)
- **AAVE_POOL_ADDRESS**: `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` (Aave Pool on Base Mainnet)
- **USDC_ADDRESS**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (Canonical USDC on Base Mainnet)

**Note**: Merchants must register with the shared escrow before using the system. They can either:
1. Use the MerchantRegistrationRouter (recommended - atomic registration and proxy deployment):
```solidity
// Merchant calls this function themselves (msg.sender is used as merchantPayout)
router.registerMerchantAndDeployProxy(arbiter)
```
2. Register directly with escrow:
```solidity
// Merchant calls this function themselves (msg.sender is used as merchantPayout)
escrow.registerMerchant(arbiter)
```

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
