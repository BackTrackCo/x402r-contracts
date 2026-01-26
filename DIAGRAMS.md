# Contract Diagrams and Visualization

## Inheritance Diagram

An inheritance diagram has been generated showing the contract inheritance structure.

### Prerequisites

Install Graphviz:

```bash
# macOS
brew install graphviz

# Ubuntu/Debian
sudo apt-get install graphviz

# Windows (via Chocolatey)
choco install graphviz
```

### Rendering the Diagram

The inheritance graph is available as `inheritance-graph.dot`. To render it:

```bash
# Generate PNG
dot -Tpng inheritance-graph.dot -o inheritance-graph.png

# Generate SVG (scalable, recommended for documentation)
dot -Tsvg inheritance-graph.dot -o inheritance-graph.svg

# Generate PDF
dot -Tpdf inheritance-graph.dot -o inheritance-graph.pdf
```

### Viewing the Diagram

- **PNG/SVG**: Open with any image viewer
- **PDF**: Open with any PDF viewer
- **Online**: Upload the .dot file to [Graphviz Online](https://dreampuf.github.io/GraphvizOnline/)

### What the Diagram Shows

The inheritance diagram displays:
- Contract inheritance relationships
- Interface implementations
- Library usage
- Contract dependencies

**Key contracts**:
- `PaymentOperator` - Main operator with pluggable conditions
- `AuthCaptureEscrow` - Core escrow contract
- `EscrowPeriodCondition` - Time-based release conditions
- `RefundRequest` - Refund request management
- Condition combinators (And, Or, Not)

### Updating the Diagram

To regenerate after contract changes:

```bash
# Using Solidity Visual Developer (VS Code extension)
# Right-click on main contract → "Solidity: Generate Inheritance Graph"

# Or using Slither
slither . --print inheritance-graph

# Or using Surya
surya inheritance src/commerce-payments/operator/arbitration/PaymentOperator.sol | dot -Tpng -o inheritance.png
```

---

## Call Graph Diagrams

For more detailed analysis, you can generate call graphs:

```bash
# Generate call graph for specific contract
slither . --print call-graph

# This creates multiple .dot files showing function call relationships
```

---

## Contract Summary Diagrams

Generate human-readable contract summaries:

```bash
# Contract summary (functions, modifiers, events)
slither . --print contract-summary

# Human summary (complexity, dependencies)
slither . --print human-summary

# Function summary (visibility, modifiers)
slither . --print function-summary
```

---

## Architecture Diagram

For a high-level architecture overview, see the [ARCHITECTURE.md](ARCHITECTURE.md) file which includes:
- System components
- Data flow diagrams
- Integration patterns
- Trust boundaries

---

## Troubleshooting

### "dot: command not found"

Graphviz is not installed. Follow the installation instructions above.

### "Error opening file for output"

Check file permissions and disk space:

```bash
df -h .  # Check disk space
ls -la inheritance-graph.dot  # Check file exists and is readable
```

### "syntax error in line X"

The .dot file may be corrupted. Regenerate it:

```bash
# Backup old file
mv inheritance-graph.dot inheritance-graph.dot.bak

# Regenerate
slither . --print inheritance-graph
```

### Large diagrams are unreadable

For large codebases, filter to specific contracts:

```bash
# Generate for specific contract only
slither src/commerce-payments/operator/arbitration/PaymentOperator.sol --print inheritance-graph

# Or use SVG format which is scalable
dot -Tsvg inheritance-graph.dot -o inheritance-graph.svg
```

---

## Alternative Visualization Tools

### Solidity Visual Developer (VS Code)

Install extension and use:
- Contract Overview
- Generate UML diagrams
- Interactive inheritance graphs

### Sol2UML

```bash
npm install -g sol2uml

# Generate class diagram
sol2uml class src/commerce-payments/operator/arbitration/PaymentOperator.sol -o PaymentOperator-class.svg

# Generate storage layout
sol2uml storage src/commerce-payments/operator/arbitration/PaymentOperator.sol -o PaymentOperator-storage.svg
```

### Surya

```bash
npm install -g surya

# Inheritance graph
surya inheritance src/**/*.sol | dot -Tpng -o inheritance.png

# Contract graph
surya graph src/**/*.sol | dot -Tpng -o contracts.png

# Describe contracts
surya describe src/**/*.sol
```

---

## Recommended Viewing Order

For understanding the codebase:

1. **Start with**: ARCHITECTURE.md - High-level overview
2. **Then review**: inheritance-graph.svg - Contract relationships
3. **Dive into**: SECURITY.md - Security properties
4. **Explore**: Individual contract documentation

---

## Automation

### Pre-commit Hook

Add diagram generation to git hooks:

```bash
# .git/hooks/pre-commit
#!/bin/bash
if command -v dot &> /dev/null; then
    dot -Tsvg inheritance-graph.dot -o inheritance-graph.svg
    git add inheritance-graph.svg
fi
```

### CI/CD Integration

```yaml
# .github/workflows/diagrams.yml
name: Generate Diagrams

on: [push]

jobs:
  diagrams:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Graphviz
        run: sudo apt-get install graphviz
      - name: Generate diagrams
        run: |
          dot -Tsvg inheritance-graph.dot -o inheritance-graph.svg
          dot -Tpng inheritance-graph.dot -o inheritance-graph.png
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: diagrams
          path: |
            inheritance-graph.svg
            inheritance-graph.png
```

---

## Contributing

When adding new contracts:

1. Regenerate inheritance diagram
2. Update ARCHITECTURE.md if needed
3. Commit updated diagrams with code changes
4. Document any new architectural patterns

---

## Payment Lifecycle State Machine

### State Diagram

```mermaid
stateDiagram-v2
    [*] --> NonExistent

    NonExistent --> InEscrow : authorize() or charge()

    InEscrow --> Released : release() / capture()
    InEscrow --> Settled : refundInEscrow() / partialVoid()
    InEscrow --> Expired : block.timestamp ≥ authorizationExpiry

    Released --> Settled : refundPostEscrow()
    Released --> Settled : refund window expires

    Expired --> Settled : payer reclaims

    Settled --> [*]

    note right of NonExistent
        Payment does not exist
        paymentInfos[hash].payer == address(0)
    end note

    note right of InEscrow
        Funds held in escrow
        capturableAmount > 0
        Can release or refund
        Within authorization expiry
    end note

    note right of Released
        Funds captured by receiver
        refundableAmount > 0
        Still within refund window
        Can request refund
    end note

    note right of Expired
        Authorization period ended
        capturableAmount > 0
        Payer can reclaim funds
        No longer releasable
    end note

    note right of Settled
        Final state - funds distributed
        capturableAmount == 0
        refundableAmount == 0
        No further actions possible
    end note
```

### State Transitions

#### 1. NonExistent → InEscrow

**Trigger**: `authorize()` or `charge()`

**Guards**:
- No existing payment with same hash
- Valid operator, fees, and parameters
- Condition check passes (if configured)
- Sufficient token balance/approval

**Effects**:
- Transfers tokens to escrow token store
- Creates payment record
- Sets capturableAmount
- Emits AuthorizationCreated or ChargeExecuted

**Code**: `PaymentOperator.sol:219-250` (authorize), `PaymentOperator.sol:265-299` (charge)

---

#### 2. InEscrow → Released

**Trigger**: `release()` / `capture()`

**Guards**:
- Payment exists and is in escrow (capturableAmount > 0)
- Release condition passes (if configured)
- Not expired (block.timestamp < authorizationExpiry)

**Effects**:
- Transfers funds from escrow to receiver (minus fees)
- Transfers fees to operator
- Decreases capturableAmount
- Increases refundableAmount
- Emits ReleaseExecuted

**Code**: `PaymentOperator.sol:307-335`

---

#### 3. InEscrow → Settled (via refund)

**Trigger**: `refundInEscrow()` / `partialVoid()`

**Guards**:
- Payment is in escrow (capturableAmount > 0)
- Refund condition passes (if configured)
- Caller authorized (typically receiver or arbiter)

**Effects**:
- Returns funds to payer
- Decreases capturableAmount
- If full refund: capturableAmount becomes 0 (Settled)
- Emits RefundExecuted

**Code**: `PaymentOperator.sol:344-369`

---

#### 4. InEscrow → Expired

**Trigger**: Time passes, `block.timestamp ≥ authorizationExpiry`

**Guards**:
- Payment still in escrow (capturableAmount > 0)
- Authorization expiry timestamp reached

**Effects**:
- Payment becomes reclaimable by payer
- No automatic reclaim (requires payer action)
- Release operations will revert

**Code**: `PaymentOperator.sol:517` (getPaymentState check)

---

#### 5. Released → Settled (via refund)

**Trigger**: `refundPostEscrow()`

**Guards**:
- Payment captured (refundableAmount > 0)
- Within refund window (block.timestamp < refundExpiry)
- Refund condition passes (if configured)
- Token collector can source funds

**Effects**:
- Collects tokens from receiver (via token collector)
- Returns tokens to payer
- Decreases refundableAmount
- If full refund: refundableAmount becomes 0 (Settled)
- Emits RefundExecuted

**Code**: `PaymentOperator.sol:382-408`

---

#### 6. Released → Settled (automatic)

**Trigger**: Time passes, `block.timestamp ≥ refundExpiry`

**Guards**:
- Refund window expired

**Effects**:
- No automatic transition (lazy evaluation)
- refundableAmount effectively becomes 0 (refunds not allowed)
- Payment considered settled

---

#### 7. Expired → Settled

**Trigger**: Payer reclaims via `reclaim()` (escrow function)

**Guards**:
- Payment expired (block.timestamp ≥ authorizationExpiry)
- Caller is payer

**Effects**:
- Returns capturable amount to payer
- Sets capturableAmount to 0
- Payment moves to Settled state

**Code**: Handled by escrow contract (not operator)

---

### State Query Implementation

The `getPaymentState()` function determines current state:

```solidity
// PaymentOperator.sol:495-533
function getPaymentState(PaymentInfo calldata paymentInfo)
    external view returns (PaymentState state)
{
    bytes32 hash = ESCROW.getHash(paymentInfo);

    // 1. Check if payment exists
    if (paymentInfos[hash].payer == address(0)) {
        return PaymentState.NonExistent;
    }

    // 2. Get escrow state
    (bool hasCollected, uint120 capturable, uint120 refundable) =
        ESCROW.paymentState(hash);

    if (!hasCollected) return PaymentState.NonExistent;

    // 3. Check expiration
    if (capturable > 0 && block.timestamp >= paymentInfo.authorizationExpiry) {
        return PaymentState.Expired;
    }

    // 4. Determine based on amounts
    if (capturable > 0) return PaymentState.InEscrow;
    if (refundable > 0) return PaymentState.Released;
    return PaymentState.Settled;
}
```

---

## Sequence Diagrams

### Authorize Flow

```mermaid
sequenceDiagram
    participant User
    participant PaymentOperator
    participant Condition
    participant Escrow
    participant TokenCollector
    participant Recorder

    User->>PaymentOperator: authorize(paymentInfo, amount)

    Note over PaymentOperator: Access Control Checks
    PaymentOperator->>PaymentOperator: nonReentrant guard
    PaymentOperator->>PaymentOperator: validOperator modifier
    PaymentOperator->>PaymentOperator: validFees modifier

    alt AUTHORIZE_CONDITION != address(0)
        PaymentOperator->>Condition: check(paymentInfo, msg.sender)
        Condition-->>PaymentOperator: return bool
        alt condition returns false
            PaymentOperator-->>User: revert ConditionNotMet()
        end
    end

    Note over PaymentOperator: State Updates (CEI Pattern)
    PaymentOperator->>PaymentOperator: Compute paymentInfoHash
    PaymentOperator->>PaymentOperator: Store paymentInfo
    PaymentOperator->>PaymentOperator: Add to payer/receiver indexes
    PaymentOperator->>PaymentOperator: emit AuthorizationCreated

    Note over PaymentOperator: External Interactions
    PaymentOperator->>Escrow: authorize(paymentInfo, amount, collector, data)
    Escrow->>TokenCollector: collectTokens(payer, amount)
    TokenCollector->>TokenCollector: Transfer tokens from payer
    TokenCollector-->>Escrow: tokens collected
    Escrow->>Escrow: Update payment state
    Escrow->>Escrow: Create token store (if first time)
    Escrow-->>PaymentOperator: success

    alt AUTHORIZE_RECORDER != address(0)
        PaymentOperator->>Recorder: record(paymentInfo, amount, msg.sender)
        Recorder->>Recorder: Update state (e.g., timestamp)
        Recorder->>Recorder: emit event
        Recorder-->>PaymentOperator: success
    end

    PaymentOperator-->>User: success
```

### Release Flow

```mermaid
sequenceDiagram
    participant User
    participant PaymentOperator
    participant Condition
    participant Escrow
    participant Receiver
    participant FeeRecipient
    participant Recorder

    User->>PaymentOperator: release(paymentInfo, amount)

    Note over PaymentOperator: Access Control
    PaymentOperator->>PaymentOperator: nonReentrant guard
    PaymentOperator->>PaymentOperator: validOperator modifier

    alt RELEASE_CONDITION != address(0)
        PaymentOperator->>Condition: check(paymentInfo, msg.sender)
        Condition-->>PaymentOperator: return bool
        alt condition returns false
            PaymentOperator-->>User: revert ConditionNotMet()
        end
    end

    Note over PaymentOperator: State Updates
    PaymentOperator->>PaymentOperator: emit ReleaseExecuted

    Note over PaymentOperator: Capture (escrow handles fees)
    PaymentOperator->>Escrow: capture(paymentInfo, amount, feeBps, feeReceiver)
    Escrow->>Escrow: Calculate fee amount
    Escrow->>Escrow: Update payment state
    Escrow->>Receiver: Transfer amount minus fees
    Escrow->>FeeRecipient: Transfer fees to operator
    Escrow-->>PaymentOperator: success

    alt RELEASE_RECORDER != address(0)
        PaymentOperator->>Recorder: record(paymentInfo, amount, msg.sender)
        Recorder-->>PaymentOperator: success
    end

    PaymentOperator-->>User: success
```

### Refund In Escrow Flow

```mermaid
sequenceDiagram
    participant User
    participant PaymentOperator
    participant Condition
    participant Escrow
    participant Payer
    participant Recorder

    User->>PaymentOperator: refundInEscrow(paymentInfo, amount)

    Note over PaymentOperator: Access Control
    PaymentOperator->>PaymentOperator: nonReentrant guard

    alt REFUND_IN_ESCROW_CONDITION != address(0)
        PaymentOperator->>Condition: check(paymentInfo, msg.sender)
        Condition-->>PaymentOperator: return bool
        alt condition returns false
            PaymentOperator-->>User: revert ConditionNotMet()
        end
    end

    Note over PaymentOperator: State Updates
    PaymentOperator->>PaymentOperator: emit RefundExecuted

    Note over PaymentOperator: Void (return to payer)
    PaymentOperator->>Escrow: partialVoid(paymentInfo, amount)
    Escrow->>Escrow: Update payment state (decrease capturable)
    Escrow->>Payer: Transfer amount back to payer
    Escrow-->>PaymentOperator: success

    alt REFUND_IN_ESCROW_RECORDER != address(0)
        PaymentOperator->>Recorder: record(paymentInfo, amount, msg.sender)
        Recorder-->>PaymentOperator: success
    end

    PaymentOperator-->>User: success
```

### Refund Post Escrow Flow

```mermaid
sequenceDiagram
    participant User
    participant PaymentOperator
    participant Condition
    participant Escrow
    participant TokenCollector
    participant Receiver
    participant Payer
    participant Recorder

    User->>PaymentOperator: refundPostEscrow(paymentInfo, amount, collector, data)

    Note over PaymentOperator: Access Control
    PaymentOperator->>PaymentOperator: nonReentrant guard

    alt REFUND_POST_ESCROW_CONDITION != address(0)
        PaymentOperator->>Condition: check(paymentInfo, msg.sender)
        Condition-->>PaymentOperator: return bool
        alt condition returns false
            PaymentOperator-->>User: revert ConditionNotMet()
        end
    end

    Note over PaymentOperator: State Updates
    PaymentOperator->>PaymentOperator: emit RefundExecuted

    Note over PaymentOperator: Refund (collect from receiver)
    PaymentOperator->>Escrow: refund(paymentInfo, amount, collector, data)
    Escrow->>TokenCollector: collectTokens(receiver, amount)

    Note over TokenCollector: Token collector enforces<br/>receiver permission<br/>(approval or signature)
    TokenCollector->>Receiver: Transfer tokens from receiver
    TokenCollector-->>Escrow: tokens collected

    Escrow->>Escrow: Update payment state (decrease refundable)
    Escrow->>Payer: Transfer amount to payer
    Escrow-->>PaymentOperator: success

    alt REFUND_POST_ESCROW_RECORDER != address(0)
        PaymentOperator->>Recorder: record(paymentInfo, amount, msg.sender)
        Recorder-->>PaymentOperator: success
    end

    PaymentOperator-->>User: success
```

### Condition Combinator Flow

```mermaid
sequenceDiagram
    participant PaymentOperator
    participant AndCondition
    participant ConditionA
    participant ConditionB
    participant ConditionC

    PaymentOperator->>AndCondition: check(paymentInfo, caller)

    Note over AndCondition: Short-circuit evaluation

    AndCondition->>ConditionA: check(paymentInfo, caller)
    ConditionA-->>AndCondition: return true

    AndCondition->>ConditionB: check(paymentInfo, caller)
    ConditionB-->>AndCondition: return false

    Note over AndCondition: Short-circuit!<br/>Don't check ConditionC

    AndCondition-->>PaymentOperator: return false

    PaymentOperator->>PaymentOperator: revert ConditionNotMet()
```

---

## Error Flow Diagrams

### Authorization Failure Paths

```mermaid
flowchart TD
    Start([User calls authorize]) --> CheckReentrancy{Reentrancy<br/>guard?}
    CheckReentrancy -->|Failed| ReentrancyError[Revert:<br/>ReentrancyGuardReentrantCall]
    CheckReentrancy -->|Passed| CheckOperator{Valid<br/>operator?}

    CheckOperator -->|No| OperatorError[Revert:<br/>InvalidOperator]
    CheckOperator -->|Yes| CheckFees{Valid<br/>fees?}

    CheckFees -->|No| FeeError[Revert:<br/>InvalidFeeBps or<br/>TotalFeeRateExceedsMax]
    CheckFees -->|Yes| CheckCondition{Condition<br/>configured?}

    CheckCondition -->|Yes| EvalCondition{Condition<br/>passes?}
    EvalCondition -->|No| ConditionError[Revert:<br/>ConditionNotMet]
    EvalCondition -->|Yes| CallEscrow

    CheckCondition -->|No| CallEscrow[Call escrow.authorize]

    CallEscrow --> EscrowCheck{Escrow<br/>succeeds?}
    EscrowCheck -->|No| EscrowError[Revert:<br/>Various escrow errors]
    EscrowCheck -->|Yes| RecorderCheck{Recorder<br/>configured?}

    RecorderCheck -->|Yes| CallRecorder{Recorder<br/>succeeds?}
    CallRecorder -->|No| RecorderError[Revert:<br/>Recorder error]
    CallRecorder -->|Yes| Success

    RecorderCheck -->|No| Success([Success])

    style ReentrancyError fill:#f88
    style OperatorError fill:#f88
    style FeeError fill:#f88
    style ConditionError fill:#f88
    style EscrowError fill:#f88
    style RecorderError fill:#f88
    style Success fill:#8f8
```

---

## Component Interaction Diagram

```mermaid
graph TD
    User[User/Integrator] -->|authorize, release, refund| PO[PaymentOperator]

    PO -->|check permissions| Cond[Conditions]
    PO -->|manage funds| Esc[AuthCaptureEscrow]
    PO -->|record state| Rec[Recorders]

    Cond -->|compose logic| Comb[Combinators<br/>And/Or/Not]
    Comb -->|delegate to| Cond

    Esc -->|store tokens| TS[TokenStore]
    Esc -->|collect tokens| TC[TokenCollector]

    Rec -->|query payment state| Esc
    Rec -->|enforce time locks| Time[EscrowPeriodRecorder]

    Time -->|freeze logic| FP[FreezePolicy]

    PO -->|distribute fees| FR[Fee Recipients]

    style PO fill:#bbf,stroke:#333,stroke-width:4px
    style Esc fill:#bfb,stroke:#333,stroke-width:2px
    style Cond fill:#fbb,stroke:#333,stroke-width:2px
    style Rec fill:#fbf,stroke:#333,stroke-width:2px
```

---

**Last Updated**: 2026-01-25
