# Arithmetic Specification

Formal specification of all arithmetic operations in x402r-contracts, mapping formulas to code locations, documenting invariants, rounding behavior, and bounds.

---

## 1. Fee Calculation

### 1.1 Single Fee Calculation

**Formula:**
```
fee = amount * feeBps / 10000
```

**Code location:** `PaymentOperator.sol` — fee is computed by the escrow layer during `release()` and `charge()`. The operator provides the fee BPS to the escrow, which performs the arithmetic.

**Bounds:**
- `amount`: `uint120` (max 1,329,227,995,784,915,872,903,807,060,280,344,575)
- `feeBps`: `uint256`, capped at 10000 by `StaticFeeCalculator` constructor and `PaymentOperator` validation
- Intermediate: `amount * feeBps` fits in `uint256` since `uint120 * 10000 << uint256.max`

**Rounding:** Solidity integer division truncates (rounds toward zero). This means:
- Fees are always rounded DOWN (in favor of the payer/receiver)
- Minimum non-zero fee: `amount >= ceil(10000 / feeBps)`. For 50 bps: `amount >= 200`
- 1 wei with any feeBps < 10000 produces 0 fee

**Test coverage:** `ArithmeticEdgeCases.t.sol:261-283` (dust amounts), `FeeCalculationFuzz.t.sol` (7 fuzz tests)

### 1.2 Combined Fee Validation

**Formula:**
```
combinedFeeBps = protocolFeeBps + operatorFeeBps
require(combinedFeeBps <= 10000)
require(combinedFeeBps >= paymentInfo.minFeeBps)
require(combinedFeeBps <= paymentInfo.maxFeeBps)
```

**Code location:** `PaymentOperator.sol` — `validFees` modifier

**Invariant:** The sum of protocol and operator fees never exceeds 100% of the payment amount.

### 1.3 Fee Split (distributeFees)

**Formula:**
```
balance = token.balanceOf(address(this))
protocolShare = min(accumulatedProtocolFees[token], balance)
operatorShare = balance - protocolShare
```

**Code location:** `PaymentOperator.sol:distributeFees()`

**Safety property:** `protocolShare` is capped to `balance` to handle theoretical rounding edge cases where accumulated protocol fees might exceed the actual balance by dust amounts.

**Proof of safety:** Protocol fees are calculated as `amount * protocolFeeBps / 10000` and accumulated via `+=`. The operator receives `amount - totalFee` where `totalFee = amount * combinedFeeBps / 10000`. Since `protocolFeeBps <= combinedFeeBps`, and fees are computed from the same `amount` in the same transaction, the accumulated protocol fees can never exceed the total fees collected. The `min()` guard is defense-in-depth.

**Test coverage:** `FeeCalculationFuzz.t.sol:testFuzz_FeeConservation`, `FoundryPaymentOperatorInvariants.t.sol:invariant_feeDistributionConservation`

---

## 2. Payment Amounts

### 2.1 Authorization Amount

**Constraint:**
```
0 < amount <= paymentInfo.maxAmount
paymentInfo.maxAmount: uint120
```

**Code location:** Escrow layer validates authorization amount.

**Invariant (P4):** `capturedAmount + refundedAmount <= authorizedAmount` for every payment.

**Test coverage:** `PaymentOperatorInvariants.sol:echidna_no_double_spend`, `FoundryPaymentOperatorInvariants.t.sol:invariant_noDoubleSpend`

### 2.2 Release Amount

**Constraint:**
```
0 < releaseAmount <= capturableAmount
```

**After release:**
```
capturableAmount' = capturableAmount - releaseAmount
receiverGets = releaseAmount - fee
fee = releaseAmount * combinedFeeBps / 10000
```

**Code location:** Escrow layer (`capture` function)

**Invariant:** `capturableAmount` is monotonically non-increasing per payment (can only decrease via release or refund).

### 2.3 Refund Amount

**Constraint:**
```
0 < refundAmount <= capturableAmount  (for refundInEscrow)
```

**After refund:**
```
capturableAmount' = capturableAmount - refundAmount
refundableAmount' = refundableAmount + refundAmount
```

**Code location:** Escrow layer (`refund` function)

**Invariant:** `capturableAmount + refundableAmount` is conserved during refundInEscrow (tokens don't leave escrow, they change bucket).

### 2.4 Refund Request Amount

**Constraint:**
```
amount > 0
nonce must be unique per (payer, paymentHash) pair
```

**Code location:** `RefundRequest.sol:requestRefund()`

---

## 3. Timestamp Arithmetic

### 3.1 Escrow Period Check

**Formula:**
```
canRelease = (block.timestamp >= authorizationTime + ESCROW_PERIOD) && !frozen
```

**Code location:** `EscrowPeriod.sol:check()`

**Overflow safety:** `authorizationTime` is `uint256` from `block.timestamp`, `ESCROW_PERIOD` is `uint256`. Sum fits in `uint256` for any realistic values (block.timestamp is ~10^10, escrow periods are ~10^6).

**Manipulation bound:** Miners can manipulate `block.timestamp` by ~15 minutes. For escrow periods of days/weeks, this is negligible.

### 3.2 Freeze Duration

**Formula:**
```
frozenUntil = block.timestamp + FREEZE_DURATION
isFrozen = (frozenUntil > block.timestamp)
```

**Code location:** `EscrowPeriod.sol:freeze()`

**Edge case:** `FREEZE_DURATION = 0` means permanent freeze (until explicit unfreeze sets `frozenUntil = 0`).

### 3.3 Expiry Checks

**Constraints:**
```
preApprovalExpiry: uint48 — max ~8.9 million years from epoch
authorizationExpiry: uint48
refundExpiry: uint48
```

**Code location:** Escrow layer validates all expiry timestamps.

**Invariant:** Expiry timestamps are monotonically reached (once `block.timestamp > expiry`, it stays expired forever since `block.timestamp` only increases).

### 3.4 Timelock Delay

**Formula:**
```
executeAfter = block.timestamp + TIMELOCK_DELAY  (TIMELOCK_DELAY = 7 days = 604800)
canExecute = (block.timestamp >= executeAfter)
```

**Code location:** `ProtocolFeeConfig.sol:queueCalculatorChange()`, `queueRecipientChange()`

---

## 4. Index Arithmetic

### 4.1 Payment Index Pagination

**Formula:**
```
remaining = total - offset
actualCount = min(remaining, count)
```

**Code location:** `PaymentIndexRecorder.sol:getPayerPayments()`, `getReceiverPayments()`

**Edge cases:**
- `offset >= total`: returns empty array
- `count == 0`: returns empty array
- `offset + count > total`: returns `total - offset` records

### 4.2 Record Count Increment

**Formula:**
```
recordCount[hash]++
payerPaymentCount[payer]++
receiverPaymentCount[receiver]++
```

**Code location:** `PaymentIndexRecorder.sol:record()`

**Overflow safety:** `uint256` counters. Would need 10^77 calls to overflow — practically impossible.

---

## 5. CREATE2 Address Computation

**Formula:**
```
address = uint160(uint256(keccak256(
    abi.encodePacked(0xff, deployer, salt, keccak256(bytecode))
)))
```

**Code locations:**
- `PaymentOperatorFactory.sol:deployOperator()`
- `StaticFeeCalculatorFactory.sol:deploy()`, `computeAddress()`
- `EscrowPeriodFactory.sol:deploy()`, `computeAddress()`
- `FreezeFactory.sol:deploy()`, `computeAddress()`

**Invariant:** `computeAddress(params) == deploy(params)` for all factories. Verified by `assert(deployed == predicted)` in every factory.

**Test coverage:** `FactoryCoverage.t.sol` tests `computeAddress` matches actual deployment for all factories.

---

## 6. Invariant Summary

| ID | Invariant | Formula | Verified By |
|----|-----------|---------|-------------|
| A1 | Fee never exceeds payment | `fee <= amount` | `feeBps <= 10000` enforced |
| A2 | No double-spend | `captured + refunded <= authorized` | Echidna + Foundry invariant tests |
| A3 | Solvency | `escrowBalance >= Σ(capturable + refundable)` | Echidna + Foundry invariant tests |
| A4 | Fee conservation | `protocolFee + operatorFee + receiverAmount == releaseAmount` | Fuzz tests |
| A5 | Protocol fees bounded | `accumulatedProtocolFees <= operatorBalance` | Echidna + Foundry invariant tests |
| A6 | Fee recipient monotonic | `recipientBalance` only increases | Echidna invariant test |
| A7 | Timestamp monotonic | `block.timestamp` never decreases | EVM guarantee |
| A8 | CREATE2 deterministic | `computeAddress == deploy address` | Factory tests + `assert()` |
| A9 | Combined fee capped | `protocolBps + operatorBps <= 10000` | `validFees` modifier |
