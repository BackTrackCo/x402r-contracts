# Gas Breakdown: Base Commerce Payments vs PaymentOperator Overhead

## Executive Summary

**Base Commerce Payments (Escrow) accounts for 75-85% of total gas costs.**

Most gas is spent in the escrow layer (which we don't control), not our operator wrapper. The operator has been optimized to store only fee-related data, with payment state queries delegated to the escrow.

---

## Current Gas Costs (v3.0)

### PaymentOperator.authorize()
- **Without indexing**: ~231,000 gas
- **With PaymentIndexRecorder**: ~273,000 gas (first) / ~253,000 gas (subsequent)

### PaymentOperator.release()
- **Base release**: ~65,000 gas
- **With conditions**: +2,000-10,000 gas per condition

### PaymentOperator.charge()
- **Direct charge**: ~285,000 gas

---

## Gas Components

### Estimated Breakdown (authorize without indexing)

| Component | Gas Cost | Percentage |
|-----------|----------|------------|
| **Base Commerce Payments (Escrow)** | ~175,000 gas | **76%** |
| **PaymentOperator Overhead** | ~56,000 gas | **24%** |
| **TOTAL** | ~231,000 gas | 100% |

---

## Escrow Layer (~76% of cost)

**What it does:**
- Token transfers (ERC20 approve/transferFrom)
- Authorization storage and state management
- Payment validation
- Escrow accounting

**Gas breakdown (estimated):**
```
Token transfer:         50,000-70,000 gas
Authorization storage:  44,000 gas (first) / 5,000 gas (subsequent)
State updates:          20,000 gas
Events:                 2,000 gas
Logic:                  10,000 gas
─────────────────────────────────────
Total escrow:          ~175,000 gas
```

**Optimization potential:** ❌ **None** - we don't control this code

---

## Operator Layer (~24% of cost)

**What it does:**
- Fee calculation and locking
- Access control (conditions)
- Event recording (optional recorders)
- Fee distribution
- Reentrancy protection

### Operator Overhead Breakdown

**Total overhead: ~56,000 gas (24%)**

```
Reentrancy guard:       2,000 gas
Condition check:        2,000 gas (if address(0))
Fee calculation:        3,000 gas
Fee locking storage:    22,000 gas (first) / 5,000 gas (subsequent)
Event emission:         1,500 gas
Recorder call:          2,000 gas (if address(0))
Function overhead:      1,000 gas
Validations & misc:    22,500 gas
─────────────────────────────────────
Total overhead:        ~56,000 gas
```

---

## Optimization History

### v1.0 (Array-Based Indexing + Full PaymentInfo Storage)
```
First payment:     473,000 gas
Subsequent:        473,000 gas
```

### v2.0 (Mapping + Counter Indexing)
```
First payment:     407,981 gas (-14%)
Subsequent:        287,059 gas (-39%)
```

### v3.0 (Current - Minimal Storage, Optional Indexing)
```
Without indexing:  231,000 gas (-43% from v2.0)
With indexing:     273,000 gas (-33% from v2.0)
```

**Key changes in v3.0:**
- Removed `paymentInfos` mapping (PaymentInfo no longer stored in operator)
- Removed view functions (`getPaymentState`, `isInEscrow`, etc.) - query escrow directly
- Added fee locking (stores only `totalFeeBps` + `protocolFeeBps` = 2 slots)
- Indexing moved to optional `PaymentIndexRecorder`

---

## Optional Features Gas Cost

### PaymentIndexRecorder

Adds on-chain payment indexing by payer/receiver.

| Operation | Additional Gas |
|-----------|----------------|
| First payment | +42,000 gas |
| Subsequent | +22,000 gas |

**Use when:** Need on-chain payment queries
**Skip when:** Using external indexer (The Graph)

### Conditions

| Condition Type | Gas Cost |
|----------------|----------|
| address(0) (always allow) | ~100 gas |
| Simple condition | ~2,000 gas |
| And/Or combinator (2 conditions) | ~4,000 gas |
| Complex combinator (5 conditions) | ~10,000 gas |

**Recommended:** Keep combinator depth ≤ 5

---

## Key Insights

### 1. Most Cost is Escrow (76%)

The majority of gas is spent in Base Commerce Payments escrow layer:
- Token transfers
- Authorization storage
- State management

**We cannot optimize this** - it's external infrastructure.

### 2. Minimal Operator Storage

The operator now stores only:
- `authorizedFees[hash]` - 2 slots (totalFeeBps, protocolFeeBps)
- `accumulatedProtocolFees[token]` - 1 slot per token

PaymentInfo is NOT stored - query escrow via `escrow.paymentState(hash)`.

### 3. Optional Indexing

Payment indexing is optional via `PaymentIndexRecorder`:
- **With indexing**: +42k gas first, +22k subsequent
- **Without indexing**: Use external indexer (The Graph) for queries

---

## Recommendations

### ✅ Default: No Indexing
**Gas cost**: ~231,000 gas per authorize
**Trade-off**: Use external indexer for payment queries
**Best for**: Most use cases

### ⚠️ Optional: With PaymentIndexRecorder
**Gas cost**: ~273,000 gas per authorize
**Trade-off**: On-chain payment queries, higher gas
**Best for**: Protocols requiring on-chain payment lookups

### ⚠️ Optional: Built-in Batching
**Gas cost**: ~6-8% savings for batches of 10+
**Trade-off**: API complexity
**Best for**: High-volume use cases (subscriptions, payroll)

---

## Conclusion

**The operator is now optimized to minimal overhead (~24% of total gas).**

The bottleneck is Base Commerce Payments escrow (76%), which we don't control.

Focus future work on:
1. Use-case-specific optimizations (batching for high-volume users)
2. Developer experience (documentation, tooling, examples)
3. New features (not just gas optimization)

---

**Version**: 3.0.0
**Date**: 2026-01-30
**Based on**: Gas snapshot measurements after fee locking + minimal storage refactor
