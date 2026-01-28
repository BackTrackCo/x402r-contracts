# Security Policy

## Reporting a Vulnerability

**DO NOT** create a public GitHub issue for security vulnerabilities.

### Private Disclosure

Please report security vulnerabilities via one of these methods:

1. **Email**: security@x402r.com (preferred)
2. **GitHub Security Advisories**: [Report a vulnerability](https://github.com/x402r/x402r-contracts/security/advisories/new)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Suggested fix (if any)

### Response Timeline

| Action | Timeline |
|--------|----------|
| Initial acknowledgment | 24 hours |
| Severity assessment | 48 hours |
| Fix development | 1-7 days (severity dependent) |
| Public disclosure | After fix deployed + 7 days |

---

## Incident Response Plan

### Severity Levels

| Level | Description | Examples | Response Time |
|-------|-------------|----------|---------------|
| **CRITICAL** | Active exploit, funds at risk | Reentrancy drain, access control bypass | Immediate (< 1 hour) |
| **HIGH** | Exploitable vulnerability, no active exploit | Logic error enabling theft | < 24 hours |
| **MEDIUM** | Limited impact vulnerability | DoS, griefing attacks | < 72 hours |
| **LOW** | Minor issues, best practice violations | Gas inefficiency, code quality | Next release |

### Emergency Contacts

| Role | Responsibility |
|------|---------------|
| **Security Lead** | Triage, coordinate response |
| **Contract Owner** | Execute emergency transactions |
| **Multisig Signers** | Approve emergency actions |

### Response Procedures

#### Phase 1: Detection & Triage (0-1 hour)

```
1. [ ] Confirm the vulnerability/incident
2. [ ] Assess severity level
3. [ ] Alert security lead and contract owner
4. [ ] Begin incident log documentation
5. [ ] Determine if emergency action needed
```

#### Phase 2: Containment (1-4 hours)

**For CRITICAL/HIGH severity:**

```
1. [ ] Disable fees if attack vector involves fee distribution
       - Owner calls: queueFeesEnabled(false) + executeFeesEnabled()
       - Note: 24h timelock may delay this - consider pre-queued emergency disable

2. [ ] Alert users via official channels:
       - Twitter/X
       - Discord
       - Telegram

3. [ ] Contact affected protocols/integrators

4. [ ] If funds at risk, coordinate with:
       - Block builders (Flashbots) for tx censoring
       - Exchanges for deposit monitoring
       - Bridge operators if cross-chain
```

#### Phase 3: Investigation (4-24 hours)

```
1. [ ] Root cause analysis
2. [ ] Determine scope of impact
3. [ ] Identify affected addresses/transactions
4. [ ] Develop fix or mitigation
5. [ ] Internal security review of fix
```

#### Phase 4: Remediation (24-72 hours)

```
1. [ ] Deploy fix (if contract upgrade possible)
2. [ ] For immutable contracts:
       - Deploy new version
       - Coordinate migration
       - Update integrators

3. [ ] Verify fix effectiveness
4. [ ] Monitor for continued exploitation
```

#### Phase 5: Recovery & Disclosure (72+ hours)

```
1. [ ] Assess total impact (funds lost, users affected)
2. [ ] Determine recovery options:
       - Protocol treasury compensation
       - Insurance claims
       - Negotiation with attacker (if applicable)

3. [ ] Prepare post-mortem report
4. [ ] Public disclosure (after fix + 7 days)
5. [ ] Update security documentation
```

---

## Emergency Actions

### Contract-Level Controls

| Action | Method | Timelock |
|--------|--------|----------|
| Disable fees | `queueFeesEnabled(false)` → `executeFeesEnabled()` | 24 hours |
| Rescue stuck ETH | `rescueETH()` | None (owner only) |
| Transfer ownership | `requestOwnershipHandover()` → `completeOwnershipHandover()` | 48 hours |

### Limitations (Immutable Contracts)

These contracts are **immutable** - no pause function, no upgrades:

- `ArbitrationOperator` - Cannot pause payments
- `EscrowPeriodCondition` - Cannot modify escrow period
- `FreezePolicy` instances - Cannot change freeze rules after deployment

**Mitigation for immutable contracts:**
1. Deploy new version with fix
2. Coordinate with integrators to migrate
3. Old contracts remain functional but should not be used

### Pre-positioned Emergency Actions

To reduce response time for CRITICAL incidents, consider:

```solidity
// Pre-queue a fee disable that can be executed immediately if needed
// Run this periodically to maintain a "ready" state
operator.queueFeesEnabled(false);

// If emergency occurs, execute immediately (if 24h has passed)
operator.executeFeesEnabled();

// Then re-queue for next potential emergency
operator.queueFeesEnabled(true);
// ... wait 24h ...
operator.executeFeesEnabled();
operator.queueFeesEnabled(false); // Ready for next emergency
```

---

## Monitoring & Detection

Monitor these events for anomalies:

| Event | Contract | Alert Condition |
|-------|----------|-----------------|
| `AuthorizationCreated` | PaymentOperator | Unusual volume, large amounts |
| `ReleaseExecuted` | PaymentOperator | Rapid releases, unusual patterns |
| `RefundExecuted` | PaymentOperator | High refund rate |
| `PaymentFrozen` | EscrowPeriodRecorder | Mass freezing |
| `FeesDistributed` | PaymentOperator | Unexpected distribution |

For monitoring setup guides (OpenZeppelin Defender, Tenderly, Forta), see [docs.x402r.org/monitoring](https://docs.x402r.org/monitoring).

---

## Security Properties & Invariants

The following security properties MUST hold at all times. These are tested via unit tests and Echidna property-based fuzzing.

### Payment State Machine Invariants

| ID | Property | Test Coverage |
|----|----------|---------------|
| **P1** | Once authorized, payment cannot be re-authorized | Unit tests |
| **P2** | Payment can only be captured if in escrow (capturableAmount > 0) | Unit tests |
| **P3** | Payment can only be refunded if refundableAmount > 0 | Unit tests |
| **P4** | Sum of (captured + refunded) ≤ authorized amount (no double-spend) | Echidna invariant |
| **P5** | After release/refund, payment is in terminal state (no further actions) | Unit tests |

### Escrow Period Invariants

| ID | Property | Test Coverage |
|----|----------|---------------|
| **P6** | Freeze can only occur during escrow period | EscrowPeriodCondition.t.sol |
| **P7** | Release cannot occur before escrow period expires (unless unfrozen) | EscrowPeriodCondition.t.sol |
| **P8** | Frozen payments cannot be released until unfrozen | EscrowPeriodConditionInvariants.sol |
| **P9** | Escrow period clock starts at authorization time | Unit tests |
| **P10** | If authTime == 0, payment not yet authorized | Unit tests |

### Access Control Invariants

| ID | Property | Test Coverage |
|----|----------|---------------|
| **P11** | Only owner can change fee configuration | Unit tests + Echidna |
| **P12** | Fee changes require 24-hour timelock execution | Unit tests |
| **P13** | Condition checks are pure/view (no state modification) | Solidity type system |
| **P14** | Recorders execute after successful action (idempotent) | Code review |
| **P15** | address(0) condition = always allow (default behavior) | Unit tests |

### Fee Calculation Invariants

| ID | Property | Test Coverage |
|----|----------|---------------|
| **P16** | Protocol fee ≤ configured feeBasisPoints | Echidna invariant |
| **P17** | Fee split between protocol and receiver | Unit tests |
| **P18** | Fees only collected on successful release/refund | Unit tests |
| **P19** | Owner can only withdraw accumulated fees (not user funds) | Unit tests |

### Token Integration Invariants

| ID | Property | Test Coverage |
|----|----------|---------------|
| **P20** | Balance validation: tokenStoreBalanceAfter == tokenStoreBalanceBefore + amount | AuthCaptureEscrow._collectTokens |
| **P21** | No infinite approvals (ERC-3009 one-time preapproval) | AuthCaptureEscrow architecture |
| **P22** | Reentrancy protection on all state-changing functions | ReentrancyGuardTransient |
| **P23** | Failed token transfer causes entire transaction to revert | SafeTransferLib |

### Verifying Properties

**Unit Tests:**
```bash
forge test --match-path test/PaymentOperator.t.sol
forge test --match-path test/EscrowPeriodCondition.t.sol
forge test --match-path test/ReentrancyAttack.t.sol
```

**Echidna Property Testing:**
```bash
echidna . --contract PaymentOperatorInvariants --config echidna.yaml
echidna . --contract EscrowPeriodConditionInvariants --config echidna.yaml
```

**Slither Static Analysis:**
```bash
slither . --exclude-informational --exclude-low
```

---

## Escrow Trust Boundary

### Architecture Trust Model

The x402r payment system has a clear trust boundary between the trustless escrow layer and the trusted operator layer:

```
┌─────────────────────────────────────────────────────┐
│                  TRUSTLESS LAYER                     │
│                                                     │
│  AuthCaptureEscrow + TokenStore                     │
│  - Enforces payment state machine                   │
│  - Balance verification on every operation          │
│  - Reentrancy guards (ReentrancyGuardTransient)     │
│  - Cannot be manipulated by operator or conditions  │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                   TRUSTED LAYER                      │
│                                                     │
│  PaymentOperator + Conditions + Recorders           │
│  - Operator deployer chooses all plugins            │
│  - Immutable after deployment (no upgrades)         │
│  - Users must trust operator configuration          │
│  - Conditions can block/allow operations            │
│  - Recorders execute post-action callbacks          │
└─────────────────────────────────────────────────────┘
```

### What the Escrow Protects Against

The escrow layer provides hard guarantees that **no operator, condition, or recorder can violate**:

- **Fund extraction**: Escrow enforces `captured + refunded <= authorized` per payment. No amount of operator manipulation can extract more than what was authorized.
- **Balance manipulation**: Every token transfer is verified via `balanceAfter == balanceBefore + amount`. Fee-on-transfer or rebasing tokens are rejected.
- **Double-spend**: Payment state transitions are enforced at the escrow level. A payment cannot be captured and fully refunded simultaneously.
- **Unauthorized access**: Only the registered operator can call escrow functions for its payments.

### What Operators CAN Do (Trusted Risks)

Operators control the business logic layer. A malicious or buggy operator **can**:

- **Block releases**: A malicious `RELEASE_CONDITION` can return `false` indefinitely, trapping funds until `authorizationExpiry` when the payer can reclaim.
- **Censor users**: Conditions with blocklists can selectively prevent specific addresses from interacting.
- **Leak MEV**: Non-`view` conditions (should never be used) could emit events or make external calls that leak payment data to MEV bots.
- **Front-run refunds**: Without an escrow period (`RELEASE_CONDITION = address(0)`), a receiver can release funds before a refund request is processed.
- **Gas grief**: Conditions or recorders with unbounded loops can make operations fail with out-of-gas.

### Implications

**For users**: Always verify the operator's condition and recorder contracts before interacting. Use operators deployed by trusted parties with audited conditions from the safe condition library.

**For operators**: Deploy with audited conditions, use escrow periods for dispute resolution, and document trust assumptions for your users. See [OPERATOR_SECURITY.md](./OPERATOR_SECURITY.md) for the full deployment checklist.

---

## Combinator Depth Limits

### Maximum Combinator Depth Recommendation

**Protocol Enforced Limit**: `MAX_CONDITIONS = 10`

The condition combinator architecture (AndCondition, OrCondition, NotCondition) allows nesting but has a hard limit to prevent gas exhaustion and stack depth issues.

#### Why Depth Matters

```solidity
// Example: Depth 3 combinator
AndCondition(
    OrCondition(
        PayerCondition(),          // Depth 2
        ReceiverCondition()        // Depth 2
    ),
    NotCondition(
        StaticAddressCondition(arbiter)  // Depth 2
    )
)
// Total depth: 3 levels
```

**Gas costs scale with depth:**
- Depth 1: ~5k gas
- Depth 3: ~15k gas
- Depth 5: ~30k gas
- Depth 10: ~60k gas (maximum)

#### Recommendations

| Depth | Status | Use Case | Risk |
|-------|--------|----------|------|
| 1-2 | ✅ Recommended | Simple logic, low gas | None |
| 3-4 | ⚠️ Acceptable | Moderate complexity | Moderate gas |
| 5-7 | ⚠️ Use sparingly | Complex requirements | High gas, hard to audit |
| 8-10 | ❌ Avoid | Emergency only | Very high gas, difficult to understand |
| 11+ | ❌ Blocked | N/A | Protocol enforces MAX_CONDITIONS = 10 |

#### Best Practices

1. **Keep it simple**: Use 1-2 levels when possible
2. **Test gas costs**: Profile actual gas usage before deployment
3. **Document logic**: Complex combinators are hard to audit
4. **Consider alternatives**: Custom condition might be clearer than deep nesting
5. **Audit carefully**: Deep nesting can hide bugs

#### Example: Good vs Bad

**✅ GOOD** (Depth 2):
```solidity
// Receiver can release after escrow period
AndCondition(
    ReceiverCondition(),
    EscrowPeriodCondition(recorder)
)
```

**⚠️ ACCEPTABLE** (Depth 3):
```solidity
// Receiver OR arbiter can release after escrow, but not if frozen
AndCondition(
    OrCondition(
        ReceiverCondition(),
        StaticAddressCondition(arbiter)
    ),
    NotCondition(
        FrozenCondition(recorder)
    )
)
```

**❌ BAD** (Depth 6+):
```solidity
// Too complex - hard to understand, high gas, difficult to audit
AndCondition(
    OrCondition(
        AndCondition(
            NotCondition(
                OrCondition(
                    ConditionA(),
                    ConditionB()
                )
            ),
            ConditionC()
        ),
        ConditionD()
    ),
    ConditionE()
)
// Consider writing a custom condition instead!
```

#### Testing Combinator Depth

```solidity
// Test gas costs for your combinator tree
function testCombinatorGas() public {
    uint256 gasBefore = gasleft();
    bool result = MY_COMPLEX_CONDITION.check(paymentInfo, msg.sender);
    uint256 gasUsed = gasBefore - gasleft();

    // Ensure reasonable gas usage
    assertLt(gasUsed, 50000); // 50k gas limit recommended
}
```

#### Enforcement

```solidity
// CombinatorDepthChecker.sol enforces MAX_CONDITIONS = 10
function _checkDepth(address condition, uint8 depth) internal view {
    if (depth > MAX_CONDITIONS) revert MaxConditionsExceeded();
    // Recursively check nested conditions
}
```

---

## Front-Running Risks

### MEV and Transaction Ordering Attacks

Payment operations can be vulnerable to front-running and MEV (Maximal Extractable Value) extraction. This section documents known risks and mitigations.

#### Attack Vector 1: Payment Authorization Front-Running

**Scenario**: Malicious actor monitors mempool for payment authorizations

```
1. User submits: authorize(paymentInfo, 1000 USDC)
2. Attacker sees tx in mempool
3. Attacker front-runs with higher gas price
4. If conditions allow, attacker could:
   - Void the payment before user authorizes
   - Freeze the payment (if payer)
   - Manipulate conditions (if condition is mutable - NOT the case in our design)
```

**Mitigation**:
- ✅ Conditions are immutable after operator deployment
- ✅ Salt in PaymentInfo provides uniqueness
- ⚠️ Users should use private mempools (Flashbots Protect) for sensitive transactions
- ⚠️ Consider signature-based authorization (ERC-3009) to avoid mempool exposure

**Risk Level**: **LOW** - Immutable conditions prevent most front-running attacks

---

#### Attack Vector 2: Release Front-Running by Receiver

**Scenario**: Payer requests refund, receiver front-runs with release

```
1. Payer calls: requestRefund(paymentInfo)
2. Receiver sees request in mempool
3. Receiver front-runs with: release(paymentInfo, amount)
4. Release executes first, capturing funds before refund request
```

**Mitigation**:
- ✅ RefundRequest contract tracks request status
- ✅ Release condition can check RefundRequest status
- ⚠️ Users should use refund conditions that prevent front-running
- ⚠️ Escrow period provides time for dispute resolution

**Example Safe Configuration**:
```solidity
// Deploy operator with release condition that checks RefundRequest
RefundRequestBlockerCondition {
    function check(PaymentInfo calldata paymentInfo, address) view returns (bool) {
        // Block release if refund request is pending
        RequestStatus status = REFUND_REQUEST.getRefundRequestStatus(paymentInfo);
        return status != RequestStatus.Pending;
    }
}
```

**Risk Level**: **MEDIUM** - Can be mitigated with proper conditions

---

#### Attack Vector 3: Fee Distribution Timing

**Scenario**: Owner manipulates fee withdrawal timing

```
1. Large fees accumulated in operator
2. Owner calls: withdrawFees()
3. Front-runs user payments to extract fees before fee rate change
```

**Mitigation**:
- ✅ Fee rate changes have 24-hour timelock
- ✅ Fees are separate from user funds (cannot steal user funds)
- ✅ Transparent on-chain fee accumulation
- ⚠️ Owner should be multisig to prevent single-actor manipulation

**Risk Level**: **LOW** - Timelock and transparency prevent abuse

---

#### Attack Vector 4: Condition-Based MEV

**Scenario**: Malicious condition leaks information for MEV extraction

```solidity
// DANGEROUS: Condition that emits events
contract MaliciousFrontrunCondition is ICondition {
    event PaymentAttempt(address payer, uint256 amount);

    function check(PaymentInfo calldata paymentInfo, address)
        external
        returns (bool)  // NOT view!
    {
        // Leak payment data to MEV bots
        emit PaymentAttempt(paymentInfo.payer, paymentInfo.maxAmount);
        return true;
    }
}
```

**Mitigation**:
- ✅ ONLY use `view` or `pure` conditions (enforced by design)
- ✅ Never use conditions with external calls
- ✅ Audit all conditions before deployment
- ✅ Use conditions from trusted library only

**Risk Level**: **CRITICAL if violated** - Use safe condition library only

---

#### Attack Vector 5: Timestamp Manipulation

**Scenario**: Miner/validator manipulates `block.timestamp` for advantage

```solidity
// EscrowPeriodCondition uses block.timestamp
function check(PaymentInfo calldata paymentInfo, address) view returns (bool) {
    uint256 authorizedAt = RECORDER.getAuthorizedAt(paymentInfo);
    return block.timestamp >= authorizedAt + ESCROW_PERIOD;
}
```

**Risk**: Miners can manipulate timestamp by ~900 seconds (15 minutes)

**Impact**:
- Release could happen 15 min early
- Escrow period could be shortened by 15 min

**Mitigation**:
- ⚠️ Timestamp manipulation is bounded (< 15 min)
- ⚠️ For 7-day escrow periods, 15 min variance is negligible
- ⚠️ **WARNING**: For short escrow periods (< 1 hour), use block numbers instead

**Risk Level**: **LOW** - Bounded manipulation, negligible for typical escrow periods

**Implementation Guide for Short Periods**:

For escrow periods < 1 hour, implement block-number-based conditions:

```solidity
// ❌ AVOID for periods < 1 hour
contract TimestampCondition {
    function check(PaymentInfo calldata paymentInfo) view returns (bool) {
        uint256 authorizedAt = RECORDER.getAuthorizedAt(paymentInfo);
        return block.timestamp >= authorizedAt + 30 minutes; // Risky!
    }
}

// ✅ RECOMMENDED for periods < 1 hour
contract BlockNumberCondition {
    uint256 public constant ESCROW_BLOCKS = 150; // ~30 min at 12s blocks

    function check(PaymentInfo calldata paymentInfo) view returns (bool) {
        uint256 authorizedAtBlock = RECORDER.getAuthorizedAtBlock(paymentInfo);
        return block.number >= authorizedAtBlock + ESCROW_BLOCKS;
    }
}
```

**Block Time Assumptions** (Ethereum Mainnet):
- Average: ~12 seconds per block
- 30 minutes ≈ 150 blocks
- 1 hour ≈ 300 blocks
- Variance: Block times can fluctuate by ±2 seconds

**When to Use Each**:
- **Timestamps**: Escrow periods ≥ 1 hour (manipulation < 2.5% of duration)
- **Block Numbers**: Escrow periods < 1 hour (more predictable for short durations)
- **Current Implementation**: Uses timestamps - suitable for default 7-day escrow period

---

#### Defense Strategies

1. **Use Private Mempools**
   - Flashbots Protect: https://protect.flashbots.net
   - Prevents front-running of user transactions

2. **Signature-Based Authorization**
   - Use ERC-3009 or Permit2 collectors
   - Sign offline, submit when ready
   - No mempool exposure until submission

3. **Immutable Conditions**
   - ✅ Already enforced - conditions cannot change after deployment
   - Prevents condition manipulation attacks

4. **Escrow Periods**
   - Provides time buffer for dispute resolution
   - Reduces urgency that enables front-running

5. **Multi-Sig Operators**
   - Prevents single-actor manipulation
   - Requires consensus for fee changes

6. **Monitoring & Alerts**
   - Monitor mempool for suspicious patterns
   - Alert users to front-running attempts
   - Track unusual activity

---

### MEV and Slippage Protection

#### Understanding MEV in Payment Systems

**MEV (Maximal Extractable Value)** refers to profit extracted by reordering, inserting, or censoring transactions within a block. While traditional MEV targets DEX swaps and liquidations, payment systems face unique MEV risks.

**Payment-Specific MEV Vectors**:
1. **Front-running payment releases** to extract value before recipient
2. **Sandwiching fee distributions** to manipulate fee calculations
3. **Back-running authorizations** to immediately trigger related actions
4. **Censoring refund requests** to force fund capture

---

#### Slippage Protection Patterns

Unlike AMM swaps, payment systems don't have traditional "slippage" (price impact), but they have **timing slippage** (value loss due to transaction ordering).

**Pattern 1: Deadline Parameters**

```solidity
// Add deadline to critical operations
function releaseWithDeadline(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    uint256 deadline  // Timestamp after which tx reverts
) external {
    require(block.timestamp <= deadline, "Transaction expired");
    release(paymentInfo, amount);
}
```

**Use Case**: Prevent transactions from executing hours later with stale conditions

**Pattern 2: Min/Max Amount Guards**

```solidity
// Protect against unexpected fee changes
function authorizeWithMaxFee(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    uint256 maxFeeBps  // Revert if fees exceed this
) external {
    require(currentFeeBps <= maxFeeBps, "Fees too high");
    authorize(paymentInfo, amount, collector, data);
}
```

**Use Case**: Prevent fee manipulation between authorization and capture

**Pattern 3: Expected State Guards**

```solidity
// Verify payment state matches expectations
function releaseWithExpectedState(
    PaymentInfo calldata paymentInfo,
    uint256 amount,
    uint256 expectedCapturableAmount
) external {
    (, uint256 capturable, ) = ESCROW.paymentState(getHash(paymentInfo));
    require(capturable == expectedCapturableAmount, "State changed");
    release(paymentInfo, amount);
}
```

**Use Case**: Detect front-running that modified payment state

---

#### MEV Protection Strategies

**1. Private Transaction Submission** ⭐ RECOMMENDED

Use private mempools to hide transactions from public searchers:

```
Flashbots Protect RPC: https://protect.flashbots.net
- Transactions sent directly to block builders
- No public mempool exposure
- Prevents front-running and sandwich attacks
- Free to use (MEV goes to validators)
```

**Alternative Private RPCs**:
- MEV Blocker: https://mevblocker.io
- BloXroute: https://bloxroute.com
- Eden Network: https://www.edennetwork.io

**2. Signature-Based Authorization** ⭐ RECOMMENDED

Use ERC-3009 or Permit2 to avoid mempool exposure:

```solidity
// Offline signing, online submission
1. User signs: paymentInfo + amount (offline)
2. Relayer submits: authorize(paymentInfo, amount, signature)
3. No mempool exposure until atomic execution
```

**Benefits**:
- No front-running window
- Relayer can bundle multiple operations atomically
- Users don't pay gas (relayer does)

**3. Conditional Execution Guards**

Deploy operators with anti-MEV conditions:

```solidity
contract AntiMEVReleaseCondition {
    // Prevent immediate release after authorization
    uint256 public constant MIN_DELAY = 2; // 2 blocks (~24 seconds)

    function check(PaymentInfo calldata paymentInfo, address) view returns (bool) {
        uint256 authorizedAtBlock = RECORDER.getAuthorizedAtBlock(paymentInfo);
        return block.number >= authorizedAtBlock + MIN_DELAY;
    }
}
```

**Benefits**:
- Forces delay between authorization and release
- Gives payers time to react to unexpected authorizations
- Breaks atomic MEV extraction strategies

**4. Batched Operations**

Bundle multiple operations to share MEV:

```solidity
// Instead of: authorize() -> release() (two separate txs, MEV risk)
// Use: batchAuthorizeAndRelease() (one atomic tx, no MEV window)

function batchAuthorizeAndRelease(
    PaymentInfo[] calldata payments,
    uint256[] calldata amounts
) external {
    for (uint256 i = 0; i < payments.length; i++) {
        authorize(payments[i], amounts[i], collector, "");
        release(payments[i], amounts[i]);
    }
}
```

**5. Rate Limiting and Circuit Breakers**

Limit damage from MEV exploitation:

```solidity
// Prevent rapid-fire exploitation
contract RateLimitedOperator {
    mapping(address => uint256) public lastOperationTime;
    uint256 public constant COOLDOWN = 1 hours;

    modifier rateLimited() {
        require(
            block.timestamp >= lastOperationTime[msg.sender] + COOLDOWN,
            "Rate limited"
        );
        lastOperationTime[msg.sender] = block.timestamp;
        _;
    }
}
```

---

#### MEV Impact Assessment

| MEV Type | Likelihood | Impact | Current Mitigation | Recommendation |
|----------|-----------|--------|-------------------|----------------|
| **Front-running release** | Medium | Medium | Escrow period, conditions | Use private mempool |
| **Sandwich fee distribution** | Low | Low | Timelock, transparent fees | Monitor distribution txs |
| **Back-running authorization** | Low | Low | Immutable conditions | No action needed |
| **Censoring refunds** | Very Low | High | Multiple submission channels | Use private mempool |
| **Condition manipulation** | Very Low | Critical | View-only conditions | Already mitigated ✓ |

---

#### Slippage Tolerance Configuration

For integrators building on PaymentOperator:

```typescript
// Frontend integration example
interface SlippageConfig {
  // Maximum fee basis points user accepts
  maxFeeBps: number;  // e.g., 100 = 1%

  // Transaction deadline (timestamp)
  deadline: number;  // e.g., Date.now() + 600000 (10 min)

  // Minimum amount receiver accepts
  minReceivedAmount: bigint;  // After fees

  // Maximum blocks to wait for confirmation
  maxBlockDelay: number;  // e.g., 10 blocks (~2 min)
}

// Usage
const config: SlippageConfig = {
  maxFeeBps: 100,  // 1% max fees
  deadline: Math.floor(Date.now() / 1000) + 600,  // 10 min
  minReceivedAmount: amount * 99n / 100n,  // Accept 1% slippage
  maxBlockDelay: 10
};

await operator.authorizeWithProtection(
  paymentInfo,
  amount,
  config.maxFeeBps,
  config.deadline
);
```

---

#### MEV Monitoring and Alerting

**Detection Signals**:
1. **Unusually high gas prices** on payment operations
2. **Rapid authorize() → release() sequences** (< 2 blocks)
3. **Multiple failed transactions** before successful one
4. **Suspicious condition contracts** with state changes

**Recommended Monitoring**:
```bash
# Monitor mempool for payment operations
curl -X POST https://relay.flashbots.net/pending \
  -H "Content-Type: application/json" \
  -d '{"address": "0xPAYMENT_OPERATOR_ADDRESS"}'

# Alert on suspicious patterns
if (gasPrice > 100 gwei && timeSinceAuth < 2 blocks) {
  alert("Potential MEV extraction detected");
}
```

---

#### Best Practices Summary

**For Users**:
- ✅ Use private mempools (Flashbots Protect)
- ✅ Set transaction deadlines
- ✅ Specify maximum acceptable fees
- ✅ Monitor transaction status closely

**For Operators**:
- ✅ Deploy with anti-MEV conditions
- ✅ Use multi-sig for fee changes
- ✅ Implement rate limiting for sensitive operations
- ✅ Monitor for unusual transaction patterns

**For Integrators**:
- ✅ Implement slippage protection in UIs
- ✅ Use signature-based authorization (ERC-3009/Permit2)
- ✅ Batch operations when possible
- ✅ Educate users about MEV risks

---

### Front-Running Risk Matrix

| Operation | Front-Run Risk | Mitigation | Residual Risk |
|-----------|---------------|------------|---------------|
| `authorize()` | Low | Immutable conditions, salt | Minimal |
| `release()` | Medium | Escrow period, refund conditions | Low with proper setup |
| `refund()` | Low | Conditions check authorization | Minimal |
| `withdrawFees()` | Low | Timelock, multisig | Minimal |
| Condition evaluation | Critical | View-only, no external calls | Minimal if audited |

---

## Bug Bounty Program

**Coming soon** - A bug bounty program will be launched after the contracts have been audited.

---

## Post-Incident Checklist

After any security incident:

- [ ] Incident log completed with timeline
- [ ] Root cause identified
- [ ] Fix deployed and verified
- [ ] Affected users notified
- [ ] Post-mortem written
- [ ] Security documentation updated
- [ ] Monitoring rules updated
- [ ] Team retrospective conducted
- [ ] Public disclosure published (if applicable)

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-01-25 | 1.0.0 | Initial security policy |

---

## Contact

- **Security Email**: security@x402r.com
- **General Inquiries**: contact@x402r.org
- **Twitter**: [@x402rorg](https://twitter.com/x402rorg)
