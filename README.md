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
- **Address**: [`0xC409e6da89E54253fbA86C1CE3E553d24E03f6bC`](https://basescan.org/address/0xc409e6da89e54253fba86c1ce3e553d24e03f6bc)
- **Contract**: `src/simple/main/escrow/Escrow.sol:Escrow`
- **Description**: Shared escrow contract for refund extension. Merchants register with this escrow to enable deposits and refunds. Deployed with ERC4626 vault for yield generation.

### DepositRelayFactory
- **Address**: [`0x41Cc4D337FEC5E91ddcf4C363700FC6dB5f3A814`](https://basescan.org/address/0x41cc4d337fec5e91ddcf4c363700fc6db5f3a814)
- **Contract**: `src/simple/main/x402/DepositRelayFactory.sol:DepositRelayFactory`
- **Description**: Factory contract that deploys DepositRelay proxies for merchants via CREATE3. Each merchant gets a deterministic proxy address. Uses the standard CreateX address.

### DepositRelay (Implementation)
- **Address**: [`0x55eEC2951Da58118ebf32fD925A9bBB13096e828`](https://basescan.org/address/0x55eec2951da58118ebf32fd925a9bbb13096e828)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`
- **Description**: Stateless implementation contract for deposit relays. Shared across all merchants via proxy pattern. Handles ERC3009 transfers signed for the relay proxy address and forwards tokens to the escrow.

### Example ERC4626 Vault (for testing)
- **Address**: [`0x0b3fC8BA8952C6cA6807F667894b0b7c9C40FC8b`](https://basescan.org/address/0x0b3fc8ba8952c6ca6807f667894b0b7c9c40fc8b)
- **Contract**: `lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol:ERC4626Mock`
- **Description**: Example ERC4626 vault for testing purposes. This is a mock vault from OpenZeppelin that implements the ERC4626 standard. In production, merchants should deploy their own ERC4626 vaults or use existing ones (e.g., Aave aUSDC).

### Configuration
- **DEPOSIT_RELAY_FACTORY_ADDRESS**: `0x41Cc4D337FEC5E91ddcf4C363700FC6dB5f3A814`
- **SHARED_ESCROW_ADDRESS**: `0xC409e6da89E54253fbA86C1CE3E553d24E03f6bC`
- **CREATEX_ADDRESS**: `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` (Standard CreateX deployment for Base)
- **TEST_VAULT_ADDRESS**: `0x0b3fC8BA8952C6cA6807F667894b0b7c9C40FC8b` (Example vault for testing)
- **USDC_ADDRESS**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

**Note**: Merchants must register with the shared escrow before using the system:
```solidity
// Merchant calls this function themselves (msg.sender is used as merchantPayout)
escrow.registerMerchant(arbiter)
```

## Deployed Contracts (Base Sepolia)

The following contracts have been deployed and verified on Base Sepolia testnet:

### CreateX
- **Address**: [`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`](https://sepolia.basescan.org/address/0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed)
- **Contract**: `lib/createx/src/CreateX.sol:CreateX`
- **Description**: CREATE3 deployment contract used by the factory for deterministic address generation. This is the standard CreateX deployment for Base Sepolia.

### Shared Escrow
- **Address**: [`0xF7F2Bc463d79Bd3E5Cb693944B422c39114De058`](https://sepolia.basescan.org/address/0xf7f2bc463d79bd3e5cb693944b422c39114de058)
- **Contract**: `src/simple/main/escrow/Escrow.sol:Escrow`
- **Description**: Shared escrow contract for refund extension. Merchants register with this escrow to enable deposits and refunds. Deployed with ERC4626 vault for yield generation.

### DepositRelayFactory
- **Address**: [`0xf981D813842eE78d18ef8ac825eef8e2C8A8BaC2`](https://sepolia.basescan.org/address/0xf981d813842ee78d18ef8ac825eef8e2c8a8bac2)
- **Contract**: `src/simple/main/x402/DepositRelayFactory.sol:DepositRelayFactory`
- **Description**: Factory contract that deploys DepositRelay proxies for merchants via CREATE3. Each merchant gets a deterministic proxy address. Uses the standard CreateX address.

### DepositRelay (Implementation)
- **Address**: [`0x740785D15a77caCeE72De645f1bAeed880E2E99B`](https://sepolia.basescan.org/address/0x740785d15a77cacee72de645f1baeed880e2e99b)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`
- **Description**: Stateless implementation contract for deposit relays. Shared across all merchants via proxy pattern. Handles ERC3009 transfers signed for the relay proxy address and forwards tokens to the escrow.

### Example ERC4626 Vault (for testing)
- **Address**: [`0x8ABcf992AE22B60f7Ea7D384a40018b8e07a610a`](https://sepolia.basescan.org/address/0x8abcf992ae22b60f7ea7d384a40018b8e07a610a)
- **Contract**: `lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol:ERC4626Mock`
- **Description**: Example ERC4626 vault for testing purposes. This is a mock vault from OpenZeppelin that implements the ERC4626 standard. In production, merchants should deploy their own ERC4626 vaults or use existing ones (e.g., Aave aUSDC).

### Configuration
- **DEPOSIT_RELAY_FACTORY_ADDRESS**: `0xf981D813842eE78d18ef8ac825eef8e2C8A8BaC2`
- **SHARED_ESCROW_ADDRESS**: `0xF7F2Bc463d79Bd3E5Cb693944B422c39114De058`
- **CREATEX_ADDRESS**: `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` (Standard CreateX deployment for Base Sepolia)
- **TEST_VAULT_ADDRESS**: `0x8ABcf992AE22B60f7Ea7D384a40018b8e07a610a` (Example vault for testing)

### Aave v3 Pool Addresses (Base Sepolia)
- **Pool Address Provider**: `0x2642E586c52E35A7C44995ea74a8A025651ba6BD`
- **Pool Address**: `0x2Ed4E8435eFf62Eb48E613159a6a5Fe86b19fa16` (obtained via `provider.getPool()`)
- **USDC**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- **aUSDC**: `0x16da4541Ad1807f4443D92db2609C28c199c358E`

**Note**: Merchants must register with the shared escrow before using the system:
```solidity
// Merchant calls this function themselves (msg.sender is used as merchantPayout)
escrow.registerMerchant(arbiter)
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

Deploy contracts to Base Sepolia:

```shell
$ source .env
$ forge script script/Deploy.s.sol:DeployScript --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
```

### Separate Deployment Scripts

For easier testing, contracts can be deployed separately:

1. **Deploy Escrow** (independent):
   ```shell
   forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
   ```

2. **Deploy Factory** (requires Escrow address):
   ```shell
   SHARED_ESCROW_ADDRESS=0xF7F2Bc463d79Bd3E5Cb693944B422c39114De058 forge script script/DeployFactory.s.sol:DeployFactory --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
   ```

3. **Deploy Example Vault** (independent, for testing):
   ```shell
   forge script script/DeployVault.s.sol:DeployVault --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
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
