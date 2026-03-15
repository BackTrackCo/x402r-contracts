# x402r Dune Analytics Queries

SQL queries for tracking x402r protocol volume, operators, and fees across all deployed chains.

## Setup

1. Go to [dune.com](https://dune.com) and create a new query
2. Copy any `.sql` file from `queries/` into the Dune editor
3. Run it — no contract decoding submission needed (uses raw `{chain}.logs` tables)

Queries use per-chain tables (`base.logs`, `ethereum.logs`, etc.) with `UNION ALL` for cross-chain aggregation.

## Contract Addresses

Source of truth: `x402r-sdk/packages/core/src/config/index.ts`

The queries use parameterized addresses. Replace the placeholder values or use Dune parameters.

## Event Signatures (topic0)

| Event | topic0 |
|-------|--------|
| `AuthorizationCreated` | `0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d` |
| `ChargeExecuted` | `0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00` |
| `ReleaseExecuted` | `0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57` |
| `RefundInEscrowExecuted` | `0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd` |
| `RefundPostEscrowExecuted` | `0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae` |
| `FeesDistributed` | `0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e` |
| `OperatorDeployed` | `0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10` |
| `PaymentAuthorized` | `0x1c81fb2e3bab27f6bb09bee9a0dddf61600b7cbaf2c12683e4864e0cbdb9d284` |

## Queries

| File | Description |
|------|-------------|
| `volume_by_chain.sql` | Total payment volume per chain |
| `volume_by_operator.sql` | Volume broken down by operator contract |
| `payment_lifecycle.sql` | Auth → Release → Refund flow with net captured |
| `fees.sql` | Protocol and arbiter fee collection |
| `operators.sql` | All deployed operators per chain |
| `users.sql` | Unique payers and receivers |
| `volume_timeseries.sql` | Daily volume over time |

## Supported Chains

| Chain | Dune name | Factory Address |
|-------|-----------|-----------------|
| Base | `base` | `0x3D0837fF8Ea36F417261577b9BA568400A840260` |
| Ethereum | `ethereum` | `0x1e52a74cE6b69F04a506eF815743E1052A1BD28F` |
| Polygon | `polygon` | `0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8` |
| Arbitrum | `arbitrum` | `0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6` |
| Optimism | `optimism` | `0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6` |
| Celo | `celo` | `0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6` |
| Avalanche | `avalanche_c` | `0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6` |
