# Audit Documentation

## Contract Overview

**x402r Payment System** - Generic payment operator built on Base Commerce Payments with flexible condition/recorder slots.

**Version**: 0.1.0 (Beta - Unaudited)
**Optimizations**: Mapping + counter indexing pattern
**Solidity**: 0.8.28+
**Chain**: EVM-compatible (Base, Ethereum, Optimism, Arbitrum)

---

## Scope

### In-Scope Contracts

#### Core x402r Contracts

| Contract | LoC | Description |
|----------|-----|-------------|
| **PaymentOperator.sol** | ~600 | Core payment operator with condition/recorder slots |
| **PaymentOperatorAccess.sol** | ~100 | Access control modifiers and validation |
| **PaymentOperatorFactory.sol** | ~200 | Factory for deploying operators |
| **RefundRequest.sol** | ~300 | Refund request management with status tracking |
| **RefundRequestAccess.sol** | ~80 | Refund access control |
| **EscrowPeriod.sol** | ~210 | Combined escrow period recorder + condition |
| **FreezeFactory.sol** | ~120 | Factory for freeze condition instances |
| **Freeze.sol** | ~150 | Standalone freeze condition with configurable freeze/unfreeze conditions |

**Subtotal**: ~1,700 LoC

#### Base Commerce Payments Modifications

| Contract | Addition | LoC | Description |
|----------|----------|-----|-------------|
| **AuthCaptureEscrow.sol** | `partialVoid()` function | ~20 | Custom addition: Allows partial return of escrowed funds to payer |

**Addition**: 1 new function (~20 LoC)

**Total In-Scope**: ~1,720 LoC

### Out of Scope

- Base Commerce Payments core functions (authorize, capture, charge, void, reclaim) - Coinbase audited
- Solady libraries - Audited, widely used
- Test contracts and mocks

### partialVoid() Addition Details

**Function**: `partialVoid(PaymentInfo calldata paymentInfo, uint120 amount)`

**Purpose**: Enable partial refunds during escrow period by returning a specified amount (rather than entire balance) to payer.

**Location**: `lib/commerce-payments/src/AuthCaptureEscrow.sol:336-354`

**Key Features**:
- Only callable by operator
- Reduces capturable amount by specified amount
- Transfers tokens from TokenStore back to payer
- Validates amount ≤ capturable amount
- Uses reentrancy guard
- Emits `PaymentPartiallyVoided` event

**Use Case**: Enables `refundInEscrow()` in PaymentOperator to refund partial amounts instead of requiring full void.

**Security Considerations**:
- Amount validation (must not exceed capturable)
- Operator-only access (via `onlySender` modifier)
- Reentrancy protection
- State update before external call (CEI pattern)

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

EscrowPeriodFactory
    └── deploys → EscrowPeriod (combined condition + recorder)

FreezeFactory
    └── deploys → Freeze instances (with freeze/unfreeze conditions passed directly)
```

### Key Features

1. **Flexible Condition/Recorder System**: Each operation (authorize, charge, release, refund) can have custom conditions (gates) and recorders (hooks)
2. **Fee Distribution**: Automatic split between protocol and operator fees
3. **Payment Indexing**: On-chain mapping of payer/receiver → payment hashes
4. **Escrow Period**: Time-based holds with freeze capability
5. **Refund Requests**: Structured refund workflow with approval/denial

---

## Indexing Optimizations

### What Changed

**Replaced array-based indexing with mapping + counter pattern** for gas efficiency.

**Before**:
```solidity
mapping(address => bytes32[]) private payerPayments;  // Dynamic array
```

**After**:
```solidity
mapping(address => mapping(uint256 => bytes32)) private payerPayments;  // Mapping
mapping(address => uint256) public payerPaymentCount;  // Counter
```

### Gas Savings

| Scenario | Before | After | Savings |
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
   - Timelock on fee changes (7 days)

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
   - Documented in EscrowPeriod.sol

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
   - Refund requests (13 tests) - **Includes partialVoid() integration via refundInEscrow()**
   - Escrow period (3 tests)

2. **Attack Vectors**:
   - Reentrancy attacks (2 tests)
   - Weird tokens (4 tests)

3. **Property-Based**:
   - Echidna fuzzing (10 invariants)
   - 50k+ sequences tested

4. **Integration**:
   - Full authorization → release flow
   - Refund workflows (including partial refunds via partialVoid)
   - Freeze/unfreeze scenarios

**Note on partialVoid()**: Tested through `refundInEscrow()` in RefundRequest tests. The function correctly calls `ESCROW.partialVoid()` and verifies token transfers.

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

**Cost**: 44k gas first / 10k subsequent (optimized with mapping + counter)

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

1. **partialVoid() Addition (Base Commerce Payments)**
   - ⚠️ **NEW FUNCTION** - Custom addition to Coinbase's AuthCaptureEscrow
   - Amount validation correctness?
   - Reentrancy despite guard?
   - State consistency after partial void?
   - Integration with existing void/reclaim flows?
   - Edge case: partialVoid entire amount vs void()?

2. **Condition/Recorder System**
   - Can malicious conditions brick operator?
   - Can recorder state corruption affect escrow?
   - Cross-operator interference risks?

3. **Fee Distribution Logic**
   - Rounding errors in splits?
   - Fee calculation overflow risks?
   - Protocol fee evasion vectors?

4. **Indexing Storage Pattern**
   - Counter overflow risks (theoretical 2^256)?
   - Pagination edge cases?
   - Storage collision risks?

5. **Freeze/Release Race Condition**
   - MEV exploitation at boundary?
   - Timestamp manipulation risks?
   - Front-running scenarios?

6. **Refund Request State Machine**
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

1. **partialVoid() Addition**: Is our custom addition to AuthCaptureEscrow secure? Any edge cases with partial vs full void? Should we add additional validation?

2. **Condition System**: Any security concerns with allowing arbitrary external condition contracts?

3. **Recorder System**: Can recorder reentrancy cause issues despite operator reentrancy guard?

4. **Mapping + Counter**: Any edge cases with the optimized indexing pattern?

5. **Fee Distribution**: Is the split calculation secure against rounding exploits?

6. **Freeze Race**: Beyond documentation, any way to mitigate the MEV risk at escrow boundary?

7. **Solady Assembly**: Any concerns with using Solady's assembly-optimized libraries?

8. **Immutable Design**: Any upgrade scenarios we're missing by being immutable?

9. **Token Handling**: Are our weird token checks (balance verification, rebase detection) sufficient?

10. **partialVoid Integration**: Does refundInEscrow() correctly integrate with partialVoid()? Any state inconsistency risks?

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
**Optimizations**: Mapping + counter indexing pattern
**Status**: Ready for audit quote
