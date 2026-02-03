# Monitoring

Monitor deposits, refund windows, and payment events in the x402r protocol.

---

## Overview

Monitoring x402r contracts involves tracking payment states, refund windows, dispute resolution, and protocol health. This guide covers event listening, indexing, dashboards, and alerting.

> **Note:** See [README.md](../README.md) for details on contract architecture and the events each contract emits.

## Key Metrics to Track

### Payment State Transitions

Monitor the lifecycle of payments through these states:

| State | Description | Next State(s) |
|-------|-------------|---------------|
| **InEscrow** | Payment authorized, funds in escrow | Released, Settled (refunded) |
| **Released** | Funds released from escrow to receiver | Settled (completed or refunded) |
| **Settled** | Payment finalized or refunded | Terminal state |

### Critical Events

Track these contract events for operational monitoring:

```solidity
// Payment lifecycle events
event PaymentAuthorized(bytes32 indexed paymentId, address indexed payer, uint256 amount)
event PaymentReleased(bytes32 indexed paymentId, uint256 amount)
event PaymentRefunded(bytes32 indexed paymentId, uint256 amount, bool inEscrow)

// Refund request events
event RefundRequested(bytes32 indexed paymentId, address indexed requester)
event RefundApproved(bytes32 indexed paymentId, address indexed approver)
event RefundDenied(bytes32 indexed paymentId, address indexed denier)
event RefundCancelled(bytes32 indexed paymentId)

// Fee events
event ProtocolFeeCollected(bytes32 indexed paymentId, uint256 amount)
event ArbiterFeeCollected(bytes32 indexed paymentId, address indexed arbiter, uint256 amount)

// Configuration events
event FeeUpdateQueued(uint256 newMaxFeeRate, uint256 newProtocolFeePercentage, uint256 effectiveTime)
event FeeUpdateExecuted(uint256 maxFeeRate, uint256 protocolFeePercentage)
```

## Event Listening and Indexing

### Option 1: Direct Event Polling with Viem/Ethers

```typescript
import { createPublicClient, http, parseAbiItem } from 'viem';
import { base } from 'viem/chains';

const client = createPublicClient({
  chain: base,
  transport: http()
});

// Listen for payment authorizations
const unwatch = client.watchContractEvent({
  address: OPERATOR_ADDRESS,
  abi: operatorAbi,
  eventName: 'PaymentAuthorized',
  onLogs: (logs) => {
    logs.forEach((log) => {
      console.log('Payment authorized:', {
        paymentId: log.args.paymentId,
        payer: log.args.payer,
        amount: log.args.amount
      });
      // Store in database, send notifications, etc.
    });
  }
});

// Get historical events
const pastLogs = await client.getContractEvents({
  address: OPERATOR_ADDRESS,
  abi: operatorAbi,
  eventName: 'PaymentAuthorized',
  fromBlock: 0n,
  toBlock: 'latest'
});
```

### Option 2: Subgraph (The Graph)

Create a subgraph for efficient querying and indexing:

```yaml
# subgraph.yaml
specVersion: 0.0.5
schema:
  file: ./schema.graphql
dataSources:
  - kind: ethereum
    name: ArbitrationOperator
    network: base
    source:
      address: "0x..."
      abi: ArbitrationOperator
      startBlock: 12345678
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.7
      language: wasm/assemblyscript
      entities:
        - Payment
        - RefundRequest
      abis:
        - name: ArbitrationOperator
          file: ./abis/ArbitrationOperator.json
      eventHandlers:
        - event: PaymentAuthorized(indexed bytes32,indexed address,uint256)
          handler: handlePaymentAuthorized
        - event: PaymentReleased(indexed bytes32,uint256)
          handler: handlePaymentReleased
        - event: RefundRequested(indexed bytes32,indexed address)
          handler: handleRefundRequested
      file: ./src/mapping.ts
```

```graphql
# schema.graphql
type Payment @entity {
  id: ID!                          # paymentId
  payer: Bytes!
  receiver: Bytes!
  arbiter: Bytes!
  amount: BigInt!
  state: PaymentState!
  authorizedAt: BigInt!
  releasedAt: BigInt
  settledAt: BigInt
  refundRequests: [RefundRequest!]! @derivedFrom(field: "payment")
}

enum PaymentState {
  InEscrow
  Released
  Settled
}

type RefundRequest @entity {
  id: ID!                          # paymentId-requester
  payment: Payment!
  requester: Bytes!
  status: RequestStatus!
  createdAt: BigInt!
  resolvedAt: BigInt
}

enum RequestStatus {
  Pending
  Approved
  Denied
  Cancelled
}
```

> **Tip:** The Graph provides efficient GraphQL queries for complex filtering and pagination. Ideal for dashboards and analytics.

### Option 3: Custom Indexer with Postgres

Build a lightweight indexer for specific needs:

```typescript
import { createPublicClient, http } from 'viem';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const client = createPublicClient({
  chain: base,
  transport: http()
});

async function indexPayments(fromBlock: bigint) {
  const logs = await client.getContractEvents({
    address: OPERATOR_ADDRESS,
    abi: operatorAbi,
    fromBlock,
    toBlock: 'latest'
  });

  for (const log of logs) {
    if (log.eventName === 'PaymentAuthorized') {
      await pool.query(
        `INSERT INTO payments (payment_id, payer, amount, state, created_at)
         VALUES ($1, $2, $3, $4, NOW())
         ON CONFLICT (payment_id) DO NOTHING`,
        [log.args.paymentId, log.args.payer, log.args.amount, 'InEscrow']
      );
    }
  }
}

// Run every 2 seconds (Base block time)
setInterval(() => indexPayments(lastIndexedBlock), 2000);
```

## Dashboard and Analytics

### Metrics Dashboard with Grafana

Track key protocol metrics:

**Payment Volume Metrics:**
- Total payments (count and value)
- Average payment size
- Payments by state (InEscrow, Released, Settled)
- Payment success rate

**Refund Metrics:**
- Total refund requests
- Refund approval rate
- Average time to refund resolution
- In-escrow vs post-escrow refunds

**Fee Metrics:**
- Total protocol fees collected
- Total arbiter fees collected
- Fee collection by arbiter

**Time-based Metrics:**
- Average escrow period duration
- Payments nearing refund window expiry
- Active freeze policies

### Query Examples

```sql
-- Total payment volume by day
SELECT DATE(created_at) as date,
       COUNT(*) as payment_count,
       SUM(amount) as total_volume
FROM payments
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Refund rate by arbiter
SELECT arbiter,
       COUNT(*) as total_payments,
       SUM(CASE WHEN state = 'Settled' AND refunded THEN 1 ELSE 0 END) as refunds,
       (SUM(CASE WHEN state = 'Settled' AND refunded THEN 1 ELSE 0 END)::float / COUNT(*)) * 100 as refund_rate_pct
FROM payments
GROUP BY arbiter
ORDER BY total_payments DESC;

-- Payments at risk (nearing refund window expiry)
SELECT payment_id, payer, receiver, amount,
       (authorized_at + escrow_period) as expiry_time,
       EXTRACT(EPOCH FROM ((authorized_at + escrow_period) - NOW())) / 3600 as hours_remaining
FROM payments
WHERE state = 'InEscrow'
  AND (authorized_at + escrow_period) < (NOW() + INTERVAL '24 hours')
ORDER BY expiry_time ASC;
```

### Dune Analytics Dashboards

Create public dashboards with Dune:

```sql
-- Total value locked in escrow (Dune SQL)
SELECT SUM(amount / 1e6) as tvl_usdc
FROM base.logs
WHERE contract_address = 0x... -- ArbitrationOperator address
  AND topic0 = 0x... -- PaymentAuthorized event signature
  AND block_time > NOW() - INTERVAL '7' DAY
```

## Alerts and Notifications

### Critical Alerts

Set up alerts for operational issues:

1. **Payment Processing Failures**
   - Alert when: Transaction reverts on payment authorization
   - Severity: HIGH
   - Action: Investigate contract state, check gas limits

2. **Unusual Refund Activity**
   - Alert when: Refund rate > 10% in 24h window
   - Severity: MEDIUM
   - Action: Review arbiter decisions, check for abuse

3. **Fee Collection Issues**
   - Alert when: Fee collection fails
   - Severity: HIGH
   - Action: Check fee recipient address, verify contract state

4. **Escrow Period Expiry**
   - Alert when: Payment nearing expiry (< 24h remaining)
   - Severity: LOW
   - Action: Notify relevant parties, prepare for automatic release

5. **Contract Ownership Changes**
   - Alert when: Owner transfer initiated or executed
   - Severity: CRITICAL
   - Action: Verify with team, check multisig logs

### Alert Implementation

```typescript
import { createPublicClient, http } from 'viem';
import { sendAlert } from './alerts';

const client = createPublicClient({
  chain: base,
  transport: http()
});

// Monitor refund rate
async function checkRefundRate() {
  const last24h = BigInt(Math.floor(Date.now() / 1000) - 86400);

  const payments = await getPaymentsSince(last24h);
  const refunds = payments.filter(p => p.state === 'Settled' && p.refunded);

  const refundRate = (refunds.length / payments.length) * 100;

  if (refundRate > 10) {
    await sendAlert({
      severity: 'MEDIUM',
      title: 'High Refund Rate Detected',
      message: `Refund rate at ${refundRate.toFixed(2)}% (threshold: 10%)`,
      data: { refundCount: refunds.length, totalPayments: payments.length }
    });
  }
}

// Monitor ownership changes
client.watchContractEvent({
  address: OPERATOR_ADDRESS,
  abi: operatorAbi,
  eventName: 'OwnershipTransferred',
  onLogs: async (logs) => {
    await sendAlert({
      severity: 'CRITICAL',
      title: 'Contract Ownership Change',
      message: `Owner changed from ${logs[0].args.previousOwner} to ${logs[0].args.newOwner}`,
      data: logs[0]
    });
  }
});
```

### Notification Channels

Integrate with your preferred channels:
- **Discord/Slack**: Webhook notifications
- **PagerDuty**: On-call alerts for critical issues
- **Email**: Daily/weekly summary reports
- **Telegram**: Real-time payment notifications

## Health Checks

### Contract State Verification

Periodically verify contract configuration:

```bash
#!/bin/bash
# health-check.sh

OPERATOR=0x...
RPC_URL=https://mainnet.base.org

# Check owner is multisig
OWNER=$(cast call $OPERATOR "owner()" --rpc-url $RPC_URL)
echo "Owner: $OWNER"

# Check fee configuration
MAX_FEE=$(cast call $OPERATOR "maxTotalFeeRate()" --rpc-url $RPC_URL)
PROTOCOL_PCT=$(cast call $OPERATOR "protocolFeePercentage()" --rpc-url $RPC_URL)
echo "Max fee rate: $MAX_FEE basis points"
echo "Protocol fee: $PROTOCOL_PCT%"

# Check escrow balance
ESCROW=0x...
USDC=0x...
BALANCE=$(cast call $USDC "balanceOf(address)" $ESCROW --rpc-url $RPC_URL)
echo "Escrow USDC balance: $BALANCE"
```

### Performance Monitoring

Track contract gas usage and execution time:
- Average gas per payment authorization
- Average gas per refund
- Block time for payment finalization
- RPC endpoint latency

---

## Related Documentation

- [README.md](../README.md) - Contract architecture and configuration patterns
- [DEPLOYMENT.md](./DEPLOYMENT.md) - Deploy and configure x402r contracts
- [SECURITY.md](./SECURITY.md) - Security best practices and incident response
