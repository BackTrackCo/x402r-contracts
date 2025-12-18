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
- **Address**: [`0x0b3fC8BA8952C6cA6807F667894b0b7c9C40FC8b`](https://sepolia.basescan.org/address/0x0b3fc8ba8952c6ca6807f667894b0b7c9c40fc8b)
- **Contract**: `src/simple/main/factory/EscrowFactory.sol:EscrowFactory`

### DepositRelay
- **Address**: [`0xC409e6da89E54253fbA86C1CE3E553d24E03f6bC`](https://sepolia.basescan.org/address/0xc409e6da89e54253fba86c1ce3e553d24e03f6bc)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`

### FactoryRelay
- **Address**: [`0x41Cc4D337FEC5E91ddcf4C363700FC6dB5f3A814`](https://sepolia.basescan.org/address/0x41cc4d337fec5e91ddcf4c363700fc6db5f3a814)
- **Contract**: `src/simple/main/x402/FactoryRelay.sol:FactoryRelay`

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
