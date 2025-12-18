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

## Deployed Contracts (Base Sepolia)

The following contracts have been deployed and verified on Base Sepolia testnet:

### EscrowFactory
- **Address**: [`0xa155fCd256aBc676F724704006E5938C911c05FA`](https://sepolia.basescan.org/address/0xa155fcd256abc676f724704006e5938c911c05fa)
- **Contract**: `src/simple/main/factory/EscrowFactory.sol:EscrowFactory`

### DepositRelay
- **Address**: [`0xa09e1EBE63D82b47f1223f5A4230012dA743B4Fc`](https://sepolia.basescan.org/address/0xa09e1ebe63d82b47f1223f5a4230012da743b4fc)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`

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

Deploy contracts to Base Sepolia:

```shell
$ source .env
$ forge script script/Deploy.s.sol:DeployScript --rpc-url https://sepolia.base.org --broadcast --verify
```

The `--verify` flag will automatically verify contracts on Basescan using the `ETHERSCAN_API_KEY` from your `.env` file.

### Verify Contracts

Verify a deployed contract:

```shell
$ source .env
$ forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_PATH>:<CONTRACT_NAME> --chain base-sepolia
```

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
