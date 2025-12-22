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

### CreateX
- **Address**: [`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`](https://sepolia.basescan.org/address/0xba5ed099633d3b313e4d5f7bdc1305d3c28ba5ed)
- **Contract**: `lib/createx/src/CreateX.sol:CreateX`
- **Description**: CREATE3 deployment contract used by the factory for deterministic address generation. This is the standard CreateX deployment for Base Sepolia.

### Shared Escrow
- **Address**: [`0x0A7A89DAf51D6e6ACb28EEd60488453A18914C37`](https://sepolia.basescan.org/address/0x0a7a89daf51d6e6acb28eed60488453a18914c37)
- **Contract**: `src/simple/main/escrow/Escrow.sol:Escrow`
- **Description**: Shared escrow contract for refund extension. Merchants register with this escrow to enable deposits and refunds. Deployed with correct Aave pool address.

### DepositRelayFactory
- **Address**: [`0x395EfD7F43c3dA49B68A977986742f0560144e00`](https://sepolia.basescan.org/address/0x395efd7f43c3da49b68a977986742f0560144e00)
- **Contract**: `src/simple/main/x402/DepositRelayFactory.sol:DepositRelayFactory`
- **Version**: `4` (v4)
- **Description**: Factory contract that deploys DepositRelay proxies for merchants via CREATE3. Each merchant gets a deterministic proxy address. Uses the standard CreateX address. Includes versioning to allow new proxy addresses when implementation is updated.

### DepositRelay (Implementation)
- **Address**: [`0xf977CbC466DBc3B5F93B74B581bC7709900CD871`](https://sepolia.basescan.org/address/0xf977cbc466dbc3b5f93b74b581bc7709900cd871)
- **Contract**: `src/simple/main/x402/DepositRelay.sol:DepositRelay`
- **Description**: Stateless implementation contract for deposit relays. Shared across all merchants via proxy pattern. Handles ERC3009 transfers signed for the relay proxy address and forwards tokens to the escrow.

### Example ERC4626 Vault (for testing)
- **Address**: [`0xdA2502536e0E004b0AaAe30BDFd64902EA1b8849`](https://sepolia.basescan.org/address/0xda2502536e0e004b0aaae30bdfd64902ea1b8849)
- **Contract**: `lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol:ERC4626Mock`
- **Description**: Example ERC4626 vault for testing purposes. This is a mock vault from OpenZeppelin that implements the ERC4626 standard. In production, merchants should deploy their own ERC4626 vaults or use existing ones (e.g., Aave aUSDC).

### Configuration
- **DEPOSIT_RELAY_FACTORY_ADDRESS**: `0x395EfD7F43c3dA49B68A977986742f0560144e00`
- **SHARED_ESCROW_ADDRESS**: `0x0A7A89DAf51D6e6ACb28EEd60488453A18914C37`
- **CREATEX_ADDRESS**: `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` (Standard CreateX deployment for Base Sepolia)
- **VERSION**: `4` (v4)
- **TEST_VAULT_ADDRESS**: `0xdA2502536e0E004b0AaAe30BDFd64902EA1b8849` (Example vault for testing)

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
$ VERSION=4 forge script script/Deploy.s.sol:DeployScript --rpc-url https://sepolia.base.org --broadcast --verify
```

**Note**: The `VERSION` environment variable is required. Set it to `4` for the current deployment, and increment it when deploying a new factory with updated implementation.

### Separate Deployment Scripts

For easier testing, contracts can be deployed separately:

1. **Deploy Escrow** (independent):
   ```shell
   forge script script/DeployEscrow.s.sol:DeployEscrow --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
   ```

2. **Deploy Factory** (requires Escrow address):
   ```shell
   SHARED_ESCROW_ADDRESS=0x0A7A89DAf51D6e6ACb28EEd60488453A18914C37 VERSION=4 forge script script/DeployFactory.s.sol:DeployFactory --rpc-url https://sepolia.base.org --broadcast --verify --private-key $PRIVATE_KEY
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
