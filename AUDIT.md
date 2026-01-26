# Audit Documentation

## Contract Overview

**x402r Payment System** - Generic payment operator built on Base Commerce Payments with flexible condition/recorder slots.

**Version**: 0.1.0 (Beta - Unaudited)
**Optimizations**: v2.0 indexing pattern
**Solidity**: 0.8.28+
**Chain**: EVM-compatible (Base, Ethereum, Optimism, Arbitrum)

---

## Scope

### In-Scope Contracts

| Contract | LoC | Description |
|----------|-----|-------------|
| **PaymentOperator.sol** | ~600 | Core payment operator with condition/recorder slots |
| **PaymentOperatorAccess.sol** | ~100 | Access control modifiers and validation |
| **PaymentOperatorFactory.sol** | ~200 | Factory for deploying operators |
| **RefundRequest.sol** | ~300 | Refund request management with status tracking |
| **RefundRequestAccess.sol** | ~80 | Refund access control |
| **EscrowPeriodCondition.sol** | ~80 | Time-based release condition |
| **EscrowPeriodRecorder.sol** | ~160 | Authorization time tracking + freeze/unfreeze |
| **FreezePolicyFactory.sol** | ~120 | Factory for freeze policy instances |
| **PayerFreezePolicy.sol** | ~60 | Freeze policy allowing only payer to freeze |

**Total**: ~1,700 LoC

### Out of Scope

- Base Commerce Payments (AuthCaptureEscrow, collectors, etc.) - External dependency
- Solady libraries - Audited, widely used
- Test contracts and mocks

---

## Architecture

### System Design

```
PaymentOperatorFactory
    └── deploys → PaymentOperator (immutable, no upgrade)
                      ├── AUTHORIZE_CONDITION (optional)
                      ├── AUTHORIZE_RECORDER (optional)
                      ├── CHARGE_CONDITION (optional)
                      ├── CHARGE_RECORDER (optional)
                      ├── RELEASE_CONDITION (optional)
                      ├── RELEASE_RECORDER (optional)
                      ├── REFUND_IN_ESCROW_CONDITION (optional)
                      ├── REFUND_IN_ESCROW_RECORDER (optional)
                      ├── REFUND_POST_ESCROW_CONDITION (optional)
                      └── REFUND_POST_ESCROW_RECORDER (optional)

EscrowPeriodConditionFactory
    └── deploys → EscrowPeriodCondition + EscrowPeriodRecorder

FreezePolicyFactory
    └── deploys → PayerFreezePolicy instances
```

### Key Features

1. **Flexible Condition/Recorder System**: Each operation (authorize, charge, release, refund) can have custom conditions (gates) and recorders (hooks)
2. **Fee Distribution**: Automatic split between protocol and operator fees
3. **Payment Indexing**: On-chain mapping of payer/receiver → payment hashes
4. **Escrow Period**: Time-based holds with freeze capability
5. **Refund Requests**: Structured refund workflow with approval/denial

---

## v2.0 Optimizations

### What Changed

**Replaced array-based indexing with mapping + counter pattern** for gas efficiency.

**Before (v1.0)**:
```solidity
mapping(address => bytes32[]) private payerPayments;  // Dynamic array
```

**After (v2.0)**:
```solidity
mapping(address => mapping(uint256 => bytes32)) private payerPayments;  // Mapping
mapping(address => uint256) public payerPaymentCount;  // Counter
```

### Gas Savings

| Scenario | v1.0 | v2.0 | Savings |
|----------|------|------|---------|
| **First authorization** | 473k gas | 404k gas | **-69k (-14.6%)** |
| **Subsequent authorization** | 473k gas | 287k gas | **-186k (-39.3%)** |
| **Indexing write (first)** | 40k gas | 22k gas | **-18k (-45%)** |
| **Indexing write (subsequent)** | 10k gas | 5k gas | **-5k (-50%)** |

**Annual savings**: ~$1.5M/year on Ethereum L1 (1M transactions @ 30 gwei, $3000/ETH)

### API Changes

**New paginated functions** (backward compatible):
```solidity
function getPayerPayments(address payer, uint256 offset, uint256 count)
    external view returns (bytes32[] memory payments, uint256 total);

function getPayerPayment(address payer, uint256 index)
    external view returns (bytes32);
```

See `OPTIMIZATION_SUMMARY.md` for full details.

---

## Security Considerations

### Critical Areas

1. **Reentrancy Protection**
   - Uses Solady's `ReentrancyGuardTransient` (EIP-1153)
   - All state changes follow CEI pattern
   - Tested with malicious callback contracts

2. **Access Control**
   - Condition system gates each operation
   - Immutable operator address prevents unauthorized calls
   - Timelock on fee changes (24 hours)

3. **Integer Safety**
   - Solidity 0.8.28 automatic overflow checks
   - Fee calculations bounded by MAX_TOTAL_FEE_RATE
   - Counter overflow mathematically impossible (2^256 payments)

4. **Token Handling**
   - Rejects fee-on-transfer tokens (balance verification)
   - Rebasing tokens documented as unsupported
   - Uses Solady's SafeTransferLib (assembly-optimized)

5. **Freeze/Release Race Condition**
   - MEV risk at escrow period expiry boundary
   - Mitigated by freezing early + private mempool
   - Documented in EscrowPeriodRecorder.sol

### Known Limitations

1. **Rebasing Tokens**: Not supported (breaks accounting)
2. **Fee-on-Transfer Tokens**: Rejected by balance checks
3. **Escrow Boundary Race**: Documented MEV risk at expiry
4. **No Upgrade Path**: Immutable by design (deploy new operator)

See `SECURITY.md` and `OPERATOR_SECURITY.md` for details.

---

## Testing

### Test Coverage

```
Test Suites: 12 contracts
Tests: 63 total (all passing)
Coverage: 85%+ on core contracts
```

### Test Categories

1. **Unit Tests**:
   - Arithmetic edge cases (16 tests)
   - Payment indexing (15 tests)
   - Refund requests (13 tests)
   - Escrow period (3 tests)

2. **Attack Vectors**:
   - Reentrancy attacks (2 tests)
   - Weird tokens (4 tests)

3. **Property-Based**:
   - Echidna fuzzing (10 invariants)
   - 50k+ sequences tested

4. **Integration**:
   - Full authorization → release flow
   - Refund workflows
   - Freeze/unfreeze scenarios

See `FUZZING.md` for fuzzing methodology.

---

## Gas Analysis

### Cost Breakdown

**Total authorize() cost**: 408k (first) / 287k (subsequent)

| Component | First | Subsequent | % of Total |
|-----------|-------|------------|------------|
| **Base Commerce Payments** | ~250k | ~225k | **61-78%** |
| **Operator Overhead** | ~158k | ~62k | **22-39%** |

**Operator overhead includes**:
- Reentrancy guard: 2k
- Conditions/recorders: 4k
- Payment indexing: 44k (first) / 10k (subsequent)
- Storage: 108k (first) / 46k (subsequent)

**Bottleneck**: Base Commerce Payments escrow (61-78% of cost).

See `GAS_BREAKDOWN.md` for full analysis.

---

## Deployment

### Network Support

- ✅ Base (Mainnet + Sepolia)
- ✅ Ethereum (Mainnet + Sepolia)
- ✅ Optimism
- ✅ Arbitrum
- ✅ Any EVM-compatible chain with EIP-1153 support

### Deployment Safety

**Production checklist**:
1. ✅ Owner must be multisig (validated in deployment script)
2. ✅ Fee parameters validated (≤ 10000 bps)
3. ✅ Immutable addresses verified post-deployment
4. ✅ Ownership transferred to multisig
5. ✅ Contracts verified on block explorer

See `DEPLOYMENT_CHECKLIST.md` for full checklist.

---

## Dependencies

### External Contracts

| Dependency | Version | Audited | Usage |
|------------|---------|---------|-------|
| **Base Commerce Payments** | Latest | Coinbase | Escrow infrastructure |
| **Solady** | v0.0.280 | Yes | SafeTransferLib, Ownable, ReentrancyGuard |
| **OpenZeppelin** | v5.1.0 | Yes | Minimal (types only) |

### Solady Justification

**Why Solady over OpenZeppelin**:
- 20-30% gas savings
- Modern features (EIP-1153 transient storage)
- Well-audited, production-tested
- Used by major protocols (Uniswap, Coinbase)

**Trade-off**: Uses assembly (audited, battle-tested)

See `SOLADY_VS_OZ_ANALYSIS.md` for full comparison.

---

## Architectural Decisions

### 1. Immutable Operators

**Decision**: No upgrade mechanism

**Rationale**:
- Eliminates upgrade key risk
- Simpler security model
- Lower gas costs (no proxy overhead)
- Deploy new operator if needed

### 2. Generic Condition/Recorder Slots

**Decision**: 10 flexible slots vs hardcoded logic

**Rationale**:
- Composability (mix and match logic)
- Extensibility (custom conditions without redeployment)
- Separation of concerns (conditions ≠ operator)

### 3. On-Chain Indexing

**Decision**: Store payment mappings on-chain

**Rationale**:
- Decentralization (no The Graph dependency)
- Reliability (cannot be pruned/rate-limited)
- Developer UX (query payments directly)

**Cost**: 44k gas first / 10k subsequent (optimized in v2.0)

### 4. Mapping + Counter Pattern

**Decision**: Replaced dynamic arrays with mapping + counter

**Rationale**:
- 50% gas savings on writes
- Bounded query gas (pagination)
- No array growth overhead

**Trade-off**: Cannot iterate all payments in single call (use pagination)

---

## Code Maturity

### Trail of Bits Assessment

**Overall Score**: 3.22/4.0 (SATISFACTORY+)

| Category | Score | Status |
|----------|-------|--------|
| Arithmetic | 4/4 | ✅ Excellent |
| Auditing | 2/4 | ⚠️ **Needs external audit** |
| Access Controls | 4/4 | ✅ Excellent |
| Complexity | 3/4 | ✅ Good |
| Decentralization | 4/4 | ✅ Excellent |
| Documentation | 4/4 | ✅ Excellent |
| Transaction Ordering | 3/4 | ✅ Good (MEV risk documented) |
| Low-Level Code | 2/4 | ⚠️ Solady uses assembly |
| Testing | 3/4 | ✅ Good (85%+ coverage) |

### Critical Gaps

1. **No external audit** (blocking for production mainnet)
2. **Solady uses assembly** (mitigated: audited, battle-tested)
3. **Limited formal verification** (acceptable for this complexity)

---

## Audit Focus Areas

### High Priority

1. **Condition/Recorder System**
   - Can malicious conditions brick operator?
   - Can recorder state corruption affect escrow?
   - Cross-operator interference risks?

2. **Fee Distribution Logic**
   - Rounding errors in splits?
   - Fee calculation overflow risks?
   - Protocol fee evasion vectors?

3. **Indexing Storage Pattern**
   - Counter overflow risks (theoretical 2^256)?
   - Pagination edge cases?
   - Storage collision risks?

4. **Freeze/Release Race Condition**
   - MEV exploitation at boundary?
   - Timestamp manipulation risks?
   - Front-running scenarios?

5. **Refund Request State Machine**
   - Invalid state transitions?
   - Authorization bypass?
   - Post-escrow refund edge cases?

### Medium Priority

1. **Reentrancy vectors** (already tested, but verify CEI)
2. **Access control bypasses** (timelock, conditions)
3. **Token compatibility** (weird tokens edge cases)
4. **Factory deployment integrity** (initialization security)

### Low Priority

1. **Gas optimization correctness** (unchecked arithmetic safety)
2. **Event completeness** (off-chain indexing)
3. **Error message clarity** (developer UX)

---

## Questions for Auditors

1. **Condition System**: Any security concerns with allowing arbitrary external condition contracts?

2. **Recorder System**: Can recorder reentrancy cause issues despite operator reentrancy guard?

3. **Mapping + Counter**: Any edge cases with the optimized indexing pattern?

4. **Fee Distribution**: Is the split calculation secure against rounding exploits?

5. **Freeze Race**: Beyond documentation, any way to mitigate the MEV risk at escrow boundary?

6. **Solady Assembly**: Any concerns with using Solady's assembly-optimized libraries?

7. **Immutable Design**: Any upgrade scenarios we're missing by being immutable?

8. **Token Handling**: Are our weird token checks (balance verification, rebase detection) sufficient?

---

## Post-Audit Plan

1. **Implement findings** (critical/high severity)
2. **Deploy to mainnet** (after sign-off)
3. **Bug bounty program** (ImmuneFi)
4. **Continuous monitoring** (Tenderly, Defender)
5. **Regular security reviews** (quarterly)

---

## Contact

**Project**: x402r Payment System
**Repository**: https://github.com/BackTrackCo/x402r-contracts
**Documentation**: See README.md, SECURITY.md, OPERATOR_SECURITY.md
**Deployed**: Base Sepolia (testnet addresses in README)

---

**Prepared**: 2026-01-26
**Version**: 0.1.0 (Beta - Unaudited)
**Optimizations**: v2.0 indexing pattern
**Status**: Ready for audit quote
