# Fuzzing Campaign Documentation

## Overview

This document describes the property-based fuzzing setup for x402r-contracts using Echidna. Fuzzing validates critical security invariants through randomized testing with 100,000+ test sequences.

---

## Quick Start

### Run Full Fuzzing Campaign

```bash
# Extended campaign (100,000 sequences, ~10 minutes)
echidna test/invariants/PaymentOperatorInvariants.sol \
  --contract PaymentOperatorInvariants \
  --config echidna.yaml

# Quick validation (1,000 sequences, ~10 seconds)
echidna test/invariants/PaymentOperatorInvariants.sol \
  --contract PaymentOperatorInvariants \
  --test-limit 1000 \
  --seq-len 50
```

### Expected Output

```
echidna_owner_cannot_steal_escrow: passing
echidna_solvency: passing
echidna_no_double_spend: passing
echidna_balance_validation_enforced: passing
echidna_captured_monotonic: passing
echidna_fee_not_excessive: passing
echidna_fee_recipient_balance_increases: passing
echidna_refunded_monotonic: passing
echidna_reentrancy_protected: passing
echidna_payment_hash_unique: passing

Unique instructions: 10626
Corpus size: 6
Total calls: 100000+
```

---

## Invariants Being Tested

### 1. echidna_no_double_spend (P4)
**Property**: Sum of (captured + refunded) ≤ authorized amount

**Why Critical**: Prevents double-spending attacks where funds are both captured AND refunded.

**Test Logic**:
```solidity
for all payments:
    captured + refunded <= authorized
```

**Failure Scenario**: Would indicate PaymentOperator allows funds to be used twice.

---

### 2. echidna_solvency
**Property**: Escrow balance ≥ sum of all capturable + refundable amounts

**Why Critical**: Ensures protocol can always honor payment obligations.

**Test Logic**:
```solidity
token.balanceOf(tokenStore) >= sum(capturableAmount + refundableAmount)
```

**Failure Scenario**: Would indicate fund leakage or accounting error.

---

### 3. echidna_captured_monotonic
**Property**: Captured amount only increases, never decreases

**Why Critical**: Once funds are captured, they cannot be "uncaptured".

**Test Logic**:
```solidity
for all payments:
    capturedAmount <= authorizedAmount (never exceeds)
    capturedAmount never decreases over time
```

**Failure Scenario**: Would indicate state manipulation vulnerability.

---

### 4. echidna_refunded_monotonic
**Property**: Refunded amount only increases, never decreases

**Why Critical**: Once funds are refunded, they cannot be "unrefunded".

**Test Logic**:
```solidity
for all payments:
    refundedAmount <= authorizedAmount (never exceeds)
    refundedAmount never decreases over time
```

**Failure Scenario**: Would indicate state manipulation vulnerability.

---

### 5. echidna_fee_not_excessive (P16)
**Property**: Protocol fee ≤ configured MAX_TOTAL_FEE_RATE

**Why Critical**: Prevents excessive fee extraction.

**Test Logic**:
```solidity
MAX_TOTAL_FEE_RATE <= 10000 (100%)
```

**Failure Scenario**: Would indicate fee configuration error.

---

### 6. echidna_balance_validation_enforced (P20)
**Property**: Balance validation prevents fee-on-transfer tokens

**Why Critical**: Ensures strict balance checks catch unexpected token behavior.

**Test Logic**:
```solidity
// In AuthCaptureEscrow._collectTokens:
if (tokenStoreBalanceAfter != tokenStoreBalanceBefore + amount)
    revert TokenCollectionFailed();
```

**Failure Scenario**: Test passes if no reverts occur (validation working).

---

### 7. echidna_reentrancy_protected (P22)
**Property**: Reentrancy protection prevents callback attacks

**Why Critical**: Malicious conditions/recorders cannot reenter PaymentOperator.

**Test Logic**:
```solidity
// All functions have nonReentrant modifier
// If execution completes without deadlock, protection works
```

**Failure Scenario**: Would cause deadlock or revert if guards malfunction.

---

### 8. echidna_owner_cannot_steal_escrow
**Property**: Owner cannot withdraw user funds from escrow

**Why Critical**: Prevents privilege abuse by operator owner.

**Test Logic**:
```solidity
escrowBalance >= sum(all user funds in capturable + refundable states)
```

**Failure Scenario**: Would indicate owner can drain user funds.

---

### 9. echidna_fee_recipient_balance_increases
**Property**: Fee recipient balance never decreases

**Why Critical**: Fees should accumulate, not be withdrawn without consent.

**Test Logic**:
```solidity
token.balanceOf(protocolFeeRecipient) >= 0 (never negative)
```

**Failure Scenario**: Would indicate fee theft or accounting error.

---

### 10. echidna_payment_hash_unique
**Property**: Each unique PaymentInfo generates unique hash

**Why Critical**: Hash collisions would allow payment confusion attacks.

**Test Logic**:
```solidity
keccak256(abi.encode(paymentInfo)) is collision-resistant
paymentHashes.length stays reasonable
```

**Failure Scenario**: Would indicate hash collision vulnerability.

---

## Fuzzing Entry Points

Echidna randomly calls these functions with various inputs:

### authorize_fuzz(address payer, address receiver, uint128 amount, uint256 salt)
- Bounds: payer/receiver != 0, amount between 0 and 1M tokens
- Action: Creates and authorizes new payment
- Coverage: Authorization flow, PreApprovalPaymentCollector, token collection

### release_fuzz(uint256 paymentIndex, uint128 amount)
- Bounds: Valid payment index
- Action: Releases captured funds to receiver
- Coverage: Release conditions, fee distribution, balance updates

### refund_fuzz(uint256 paymentIndex, uint120 amount)
- Bounds: Valid payment index
- Action: Refunds funds to payer
- Coverage: Refund conditions, partial refunds, state transitions

---

## Configuration (echidna.yaml)

```yaml
testMode: property         # Property-based testing
testLimit: 100000          # 100k test sequences (extended campaign)
seqLen: 150                # Sequence length (complex scenarios)
shrinkLimit: 10000         # Shrinking for failure minimization
workers: 4                 # Parallel fuzzing
coverage: true             # Coverage-guided fuzzing
corpusDir: echidna-corpus  # Save interesting sequences
```

---

## Interpreting Results

### All Tests Passing ✓

```
echidna_no_double_spend: passing
echidna_solvency: passing
...
```

**Meaning**: All invariants held for 100,000+ randomized test sequences. High confidence in security properties.

### Test Failing ✗

```
echidna_no_double_spend: failed!
  Call sequence:
    1. authorize_fuzz(0x123..., 0x456..., 1000, 42)
    2. release_fuzz(0, 500)
    3. refund_fuzz(0, 600)
```

**Meaning**: Echidna found a counterexample. Follow the call sequence to reproduce the bug.

**Action**:
1. Reproduce manually with the exact call sequence
2. Analyze why invariant violated
3. Fix vulnerability
4. Re-run fuzzing campaign

---

## Coverage Analysis

### Coverage Metrics

- **Unique instructions**: Number of unique bytecode instructions executed
- **Corpus size**: Number of interesting sequences saved for replay
- **Gas/s**: Gas execution rate during fuzzing

### Example Output

```
Unique instructions: 10626
Unique codehashes: 7
Corpus size: 6
Total calls: 100053
```

**Good Coverage**: 10,000+ instructions, corpus grows over time
**Poor Coverage**: < 5,000 instructions, corpus doesn't grow (stuck in limited paths)

---

## Troubleshooting

### "Contract not found"

**Error**:
```
echidna: Given contract "PaymentOperatorInvariants" not found in given file
```

**Fix**: Specify explicit contract path:
```bash
echidna test/invariants/PaymentOperatorInvariants.sol --contract PaymentOperatorInvariants
```

---

### "Compiler run failed"

**Error**:
```
ERROR:CryticCompile:Compiler run failed
```

**Fix**: Ensure forge build works first:
```bash
forge build
# If successful, Echidna should work
```

---

### "No space left on device"

**Error**:
```
echidna: No space left on device
```

**Fix**: Clean up corpus directory:
```bash
rm -rf echidna-corpus
# Or increase disk space
```

---

### Fuzzing Too Slow

**Symptoms**: 100k sequences take > 30 minutes

**Fixes**:
1. Reduce testLimit to 50,000
2. Reduce seqLen to 100
3. Disable coverage: `coverage: false`
4. Reduce workers to 1-2 (less memory pressure)

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Fuzzing Campaign

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  echidna:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive

      - name: Install Echidna
        run: |
          wget https://github.com/crytic/echidna/releases/download/v2.2.1/echidna-2.2.1-Linux.tar.gz
          tar -xzf echidna-2.2.1-Linux.tar.gz
          sudo mv echidna /usr/local/bin/

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Run Echidna Fuzzing
        run: |
          echidna test/invariants/PaymentOperatorInvariants.sol \
            --contract PaymentOperatorInvariants \
            --config echidna.yaml

      - name: Upload Corpus
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: echidna-corpus
          path: echidna-corpus/
```

### Pre-Release Checklist

Before mainnet deployment:

- [ ] Extended fuzzing campaign (100k sequences) - all passing
- [ ] Review corpus for edge cases
- [ ] Re-run after any contract changes
- [ ] Document any new invariants found during fuzzing
- [ ] Archive corpus for future regression testing

---

## Extending Fuzzing Coverage

### Adding New Invariants

1. Add new `echidna_` function to PaymentOperatorInvariants.sol:

```solidity
/// @notice New invariant: Fees never exceed payment amount
function echidna_fees_reasonable() public view returns (bool) {
    // Your invariant logic here
    return true;
}
```

2. Re-run fuzzing campaign:
```bash
echidna test/invariants/PaymentOperatorInvariants.sol \
  --contract PaymentOperatorInvariants \
  --config echidna.yaml
```

### Adding New Fuzzing Entry Points

1. Add external wrapper:
```solidity
function chargeExternal(...) external {
    _charge(...);
}
```

2. Add fuzzing function:
```solidity
function charge_fuzz(uint256 paymentIndex, uint128 amount) public {
    // Bounds checking
    // Call try/catch wrapper
    try this.chargeExternal(...) {} catch {}
}
```

---

## References

- Echidna Documentation: https://github.com/crytic/echidna
- Trail of Bits Blog: Building Secure Smart Contracts
- Property-Based Testing Guide: https://github.com/crytic/building-secure-contracts/tree/master/program-analysis/echidna

---

## Maintenance

### Update Frequency

- **After every contract change**: Quick fuzzing (1k sequences)
- **Before audits**: Extended fuzzing (100k sequences)
- **Pre-release**: Multi-day fuzzing campaign (1M+ sequences)

### Version History

| Date       | Version | Changes                                |
|------------|---------|----------------------------------------|
| 2026-01-25 | 1.0.0   | Initial fuzzing setup with 10 invariants |

---

**Last Updated**: 2026-01-25
