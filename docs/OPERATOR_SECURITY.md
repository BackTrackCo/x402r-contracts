# Payment Operator Security Guide

## Overview

PaymentOperator is a **permissionless, pluggable architecture** that allows anyone to deploy custom payment logic using **conditions** and **recorders**. While this provides maximum flexibility, it also introduces security risks if malicious or buggy condition/recorder contracts are used.

**This document is CRITICAL for anyone deploying a PaymentOperator.**

---

## Table of Contents

1. [Threat Model](#threat-model)
2. [Malicious Condition Risks](#malicious-condition-risks)
3. [Malicious Recorder Risks](#malicious-recorder-risks)
4. [Reentrancy Considerations](#reentrancy-considerations)
5. [Safe Condition Library](#safe-condition-library)
6. [Deployment Checklist](#deployment-checklist)
7. [Incident Response](#incident-response)

---

## Threat Model

### Trust Assumptions

**PaymentOperator deployment is TRUSTED by design:**

- Operator deployer chooses all conditions and recorders
- Once deployed, conditions/recorders are **immutable** (cannot be changed)
- Users must trust the operator deployer's choice of conditions/recorders
- Malicious conditions/recorders can **block, front-run, or manipulate** payment flows

**AuthCaptureEscrow is TRUSTLESS:**

- Escrow contract enforces payment state machine
- Uses reentrancy guards and strict balance verification
- Operator cannot steal user funds directly
- But malicious conditions can DOS or censor transactions

### Attack Surface

```
User → PaymentOperator → AuthCaptureEscrow → TokenStore
          ↓                      ↓
     Conditions             Collectors
     Recorders
```

**Attack vectors:**
1. **Malicious Condition**: Blocks operations, censors users, front-runs
2. **Malicious Recorder**: Reenters during callback, manipulates state
3. **Buggy Condition**: Accidentally blocks legitimate operations
4. **Gas Griefing**: Infinite loop in condition check
5. **Front-Running**: MEV extraction via condition logic

---

## Malicious Condition Risks

### What are Conditions?

Conditions are **pre-check hooks** that run BEFORE operations:

```solidity
// Condition interface
interface ICondition {
    function check(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) external view returns (bool);
}

// Usage in PaymentOperator
if (address(RELEASE_CONDITION) != address(0)) {
    if (!RELEASE_CONDITION.check(paymentInfo, msg.sender)) {
        revert ConditionNotMet();
    }
}
```

**Condition slots** (all immutable after deployment):
- `AUTHORIZE_CONDITION`
- `CHARGE_CONDITION`
- `RELEASE_CONDITION`
- `REFUND_IN_ESCROW_CONDITION`
- `REFUND_POST_ESCROW_CONDITION`

---

### Attack 1: Denial of Service (DOS)

**Malicious condition always returns false**:

```solidity
contract MaliciousDOSCondition is ICondition {
    function check(PaymentInfo calldata, address) external pure returns (bool) {
        return false; // Always blocks!
    }
}
```

**Impact:**
- ❌ Users cannot release payments
- ❌ Merchants cannot receive funds
- ❌ Funds stuck in escrow until refundExpiry

**Mitigation:**
- Use trusted, audited conditions only
- Test condition behavior before deployment
- Ensure refund path is always available

---

### Attack 2: Selective Censorship

**Malicious condition blocks specific addresses**:

```solidity
contract MaliciousCensorCondition is ICondition {
    mapping(address => bool) public blocklist;

    function check(PaymentInfo calldata paymentInfo, address caller)
        external
        view
        returns (bool)
    {
        // Block specific users
        if (blocklist[paymentInfo.payer] || blocklist[paymentInfo.receiver]) {
            return false;
        }
        return true;
    }
}
```

**Impact:**
- ❌ Targeted users cannot make/receive payments
- ❌ Operator can add users to blocklist after deployment (if not immutable)
- ❌ Regulatory/compliance abuse

**Detection:**
- Review condition source code
- Check for mutable state (storage variables)
- Verify condition is truly immutable

---

### Attack 3: Front-Running / MEV Extraction

**Malicious condition leaks data or provides MEV**:

```solidity
contract MaliciousFrontrunCondition is ICondition {
    address public immutable operator;

    function check(PaymentInfo calldata paymentInfo, address caller)
        external
        returns (bool)  // NOTE: not view!
    {
        // Emit event that bots can watch
        emit PaymentAttempt(paymentInfo.payer, paymentInfo.maxAmount);

        // Or make external call that operator can front-run
        IFrontrunBot(operator).alertPayment(paymentInfo);

        return true;
    }
}
```

**Impact:**
- ❌ Payment data leaked to MEV bots
- ❌ Operator can front-run user transactions
- ❌ Privacy violation

**Detection:**
- Ensure condition is `view` or `pure` (no state changes)
- Review for external calls
- Check for event emissions

---

### Attack 4: Gas Griefing

**Malicious condition consumes excessive gas**:

```solidity
contract MaliciousGasGriefCondition is ICondition {
    function check(PaymentInfo calldata, address) external view returns (bool) {
        // Infinite loop or heavy computation
        for (uint256 i = 0; i < type(uint256).max; i++) {
            // Consume all gas
        }
        return true;
    }
}
```

**Impact:**
- ❌ Transactions always run out of gas
- ❌ Users waste ETH on failed transactions
- ❌ DOS without obviously returning false

**Detection:**
- Test condition with gas profiling
- Set reasonable gas limits
- Review for loops/recursion

---

### Attack 5: Complex Combinator Exploitation

**Malicious use of And/Or/Not combinators**:

```solidity
// Create deeply nested condition
AndCondition(
    OrCondition(
        NotCondition(
            AndCondition(
                // ... 10 levels deep
            )
        )
    )
)
```

**Impact:**
- ❌ Gas exhaustion from deep recursion
- ❌ Difficult to audit/understand logic
- ❌ Hidden backdoors in complex logic

**Mitigation:**
- Protocol enforces `MAX_CONDITIONS = 10` depth limit
- Avoid complex combinator trees
- Prefer simple, audited conditions

---

## Malicious Recorder Risks

### What are Recorders?

Recorders are **post-action hooks** that run AFTER operations:

```solidity
// Recorder interface
interface IRecorder {
    function record(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external;
}

// Usage in PaymentOperator
ESCROW.authorize(...);  // Main action

if (address(AUTHORIZE_RECORDER) != address(0)) {
    AUTHORIZE_RECORDER.record(paymentInfo, amount, msg.sender);  // Callback
}
```

**Recorder slots** (all immutable):
- `AUTHORIZE_RECORDER`
- `CHARGE_RECORDER`
- `RELEASE_RECORDER`
- `REFUND_IN_ESCROW_RECORDER`
- `REFUND_POST_ESCROW_RECORDER`

---

### Attack 6: Reentrancy Manipulation ❌ CRITICAL

**Malicious recorder reenters PaymentOperator during callback**:

```solidity
contract MaliciousReentrantRecorder is IRecorder {
    PaymentOperator public targetOperator;

    function record(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external {
        // Reenter during callback!
        // Note: PaymentOperator does NOT have nonReentrant guards
        targetOperator.release(paymentInfo, amount);
    }
}
```

**Impact:**
- ❌ **CRITICAL**: Recorder can manipulate payment state during callback
- ❌ Example: Call `release()` during `authorize()` callback
- ❌ Bypass business logic, create unexpected state

**Evidence from tests**:

```solidity
// test/ReentrancyAttack.t.sol:90-106
function test_ReentrancyOnAuthorize_SameFunction() public {
    // Malicious recorder successfully calls release() during authorize callback
    // Because PaymentOperator doesn't have reentrancy protection at operator level

    assertEq(capturableAmount, 0); // Already captured by malicious release
    assertEq(refundableAmount, PAYMENT_AMOUNT); // Now in refundable state
    assertEq(maliciousRecorder.reentrancyCount(), 1);
}
```

**Why this works:**
1. `operator.authorize()` is called
2. Escrow authorizes payment (has `nonReentrant`)
3. **Operator calls recorder.record()** (no reentrancy guard)
4. Malicious recorder calls `operator.release()`
5. PaymentOperator allows it (no guard)
6. Escrow processes release (separate `nonReentrant` context)

**Mitigation:**
- ✅ **Use only trusted recorders**
- ✅ **Audit recorder source code thoroughly**
- ⚠️ PaymentOperator should add `nonReentrant` guards (see Recommendation #4)

---

### Attack 7: State Manipulation

**Malicious recorder modifies external state**:

```solidity
contract MaliciousStateRecorder is IRecorder {
    mapping(bytes32 => bool) public paymentProcessed;

    function record(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external {
        bytes32 hash = keccak256(abi.encode(paymentInfo));

        // Set flag that could be used elsewhere
        paymentProcessed[hash] = true;

        // Could trigger external contracts
        IOtherContract(someAddress).callback(paymentInfo, amount);
    }
}
```

**Impact:**
- ⚠️ Recorder could coordinate with other contracts
- ⚠️ Privacy leak (payment data sent elsewhere)
- ⚠️ Unexpected side effects

**Detection:**
- Review for storage writes
- Check for external calls
- Ensure recorder is stateless

---

### Attack 8: Gas Griefing via Recorder

**Malicious recorder consumes excessive gas**:

```solidity
contract MaliciousGasRecorder is IRecorder {
    function record(PaymentInfo calldata, uint256, address) external {
        // Infinite loop
        while (true) {}
    }
}
```

**Impact:**
- ❌ All operations fail due to out-of-gas
- ❌ Users waste ETH on failed transactions
- ❌ Effective DOS

**Mitigation:**
- Test recorder with gas profiling
- Use trusted, simple recorders only

---

## Reentrancy Considerations

### Current Protection Model

**AuthCaptureEscrow**: ✅ Fully protected
```solidity
contract AuthCaptureEscrow is ReentrancyGuardTransient {
    function authorize(...) external nonReentrant { ... }
    function capture(...) external nonReentrant { ... }
    function refund(...) external nonReentrant { ... }
}
```

**PaymentOperator**: ❌ NOT protected (by design?)
```solidity
contract PaymentOperator is Ownable, PaymentOperatorAccess, IOperator {
    // No ReentrancyGuard inheritance!

    function authorize(...) external {
        ESCROW.authorize(...);  // Escrow is protected
        AUTHORIZE_RECORDER.record(...);  // Callback - can reenter!
    }
}
```

### Reentrancy Attack Flow

```
1. User calls operator.authorize()
2.   ├─> ESCROW.authorize() [PROTECTED by nonReentrant]
3.   └─> AUTHORIZE_RECORDER.record() [CALLBACK]
4.        └─> Malicious recorder calls operator.release() [NO GUARD]
5.             └─> ESCROW.capture() [PROTECTED by nonReentrant - separate context]
```

**Result**: Payment authorized and immediately released in same transaction, bypassing business logic.

---

### Recommendation: Add Operator-Level Guards

```solidity
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentOperator is Ownable, PaymentOperatorAccess, ReentrancyGuard, IOperator {

    function authorize(...) external nonReentrant validOperator(...) validFees(...) {
        // Protected against malicious recorder reentrancy
    }

    function release(...) external nonReentrant validOperator(...) validFees(...) {
        // Protected
    }

    // ... other functions
}
```

**Benefits:**
- Prevents recorder reentrancy manipulation
- Adds defense-in-depth
- Matches escrow protection level

**Tradeoff:**
- Slightly higher gas cost
- Limits legitimate multi-call patterns (if any exist)

---

## Safe Condition Library

### Audited, Safe Conditions

The following conditions are **audited and safe** to use:

#### 1. AlwaysTrueCondition ✅
```solidity
// Always allows the operation
contract AlwaysTrueCondition is ICondition {
    function check(PaymentInfo calldata, address) external pure returns (bool) {
        return true;
    }
}
```

**Use case**: Unrestricted operations (e.g., authorize anyone)
**Risk**: None

---

#### 2. PayerCondition ✅
```solidity
// Only payer can call
contract PayerCondition is ICondition {
    function check(PaymentInfo calldata paymentInfo, address caller)
        external
        pure
        returns (bool)
    {
        return caller == paymentInfo.payer;
    }
}
```

**Use case**: Payer-only operations (e.g., only payer can void)
**Risk**: None

---

#### 3. ReceiverCondition ✅
```solidity
// Only receiver can call
contract ReceiverCondition is ICondition {
    function check(PaymentInfo calldata paymentInfo, address caller)
        external
        pure
        returns (bool)
    {
        return caller == paymentInfo.receiver;
    }
}
```

**Use case**: Receiver-only operations (e.g., only merchant can release)
**Risk**: None

---

#### 4. StaticAddressCondition ✅
```solidity
// Only designated address can call
contract StaticAddressCondition is ICondition {
    address public immutable DESIGNATED_ADDRESS;

    constructor(address _designatedAddress) {
        DESIGNATED_ADDRESS = _designatedAddress;
    }

    function check(PaymentInfo calldata, address caller)
        external
        view
        returns (bool)
    {
        return caller == DESIGNATED_ADDRESS;
    }
}
```

**Use case**: Arbiter-only, treasury-only, compliance-officer-only operations
**Risk**: None (if designated address is trusted)
**WARNING**: Verify designated address is correct before deployment!

---

#### 5. EscrowPeriod ✅
```solidity
// Combined recorder + condition: records auth time, blocks release until escrow period expires
contract EscrowPeriod is AuthorizationTimeRecorder, ICondition {
    uint256 public immutable ESCROW_PERIOD;

    function check(PaymentInfo calldata paymentInfo, uint256, address)
        external
        view
        returns (bool)
    {
        return canRelease(paymentInfo);
    }
}
```

**Use case**: Payment escrow with dispute period
**Risk**: None (if recorder is trusted)
**NOTE**: Use the same EscrowPeriod address for both AUTHORIZE_RECORDER and RELEASE_CONDITION

---

#### 6. AndCondition ✅
```solidity
// Both conditions must pass
contract AndCondition is ICondition {
    ICondition public immutable CONDITION_A;
    ICondition public immutable CONDITION_B;

    function check(PaymentInfo calldata paymentInfo, address caller)
        external
        view
        returns (bool)
    {
        return CONDITION_A.check(paymentInfo, caller)
            && CONDITION_B.check(paymentInfo, caller);
    }
}
```

**Use case**: Combine multiple requirements (e.g., receiver AND escrow period)
**Risk**: Gas cost increases with depth
**WARNING**: Avoid deep nesting (max 10 levels enforced)

---

### Safe Recorders

#### 1. EscrowPeriod ✅ (also serves as condition)
```solidity
// Combined recorder + condition with freeze/unfreeze
contract EscrowPeriod is AuthorizationTimeRecorder, ICondition {
    // record() inherited from AuthorizationTimeRecorder
    // check() delegates to canRelease()
    // freeze()/unfreeze() for dispute handling
}
```

**Use case**: Track authorization time for escrow period checks
**Risk**: None (stateless, no external calls)

---

### ⚠️ Unsafe Patterns to Avoid

❌ **DO NOT use recorders that**:
- Make external calls to unknown contracts
- Have loops or heavy computation
- Store sensitive data
- Emit events with private information
- Reenter ANY function

❌ **DO NOT use conditions that**:
- Depend on mutable state (unless carefully audited)
- Make external calls
- Have owner/admin controls
- Use complex logic without audit
- Return non-deterministic values

---

## Deployment Checklist

Before deploying a PaymentOperator:

### 1. Condition Review ✅

- [ ] All conditions are from safe library OR audited
- [ ] All conditions are `view` or `pure` (no state changes)
- [ ] No external calls in conditions
- [ ] No owner/admin controls that could change behavior
- [ ] Gas tested (< 100k gas per condition)
- [ ] Combinator depth < 5 levels (protocol enforces < 10)

### 2. Recorder Review ✅

- [ ] All recorders are from safe library OR audited
- [ ] No reentrancy (no calls to operator/escrow)
- [ ] No external calls to unknown contracts
- [ ] Minimal state storage
- [ ] Gas tested (< 100k gas per recorder)

### 3. Integration Testing ✅

- [ ] Test with actual tokens (USDC, DAI, WETH)
- [ ] Test all operation paths (authorize, release, refund)
- [ ] Test edge cases (pause, revert, out-of-gas)
- [ ] Test with malicious actor scenarios
- [ ] Gas profiling completed

### 4. Documentation ✅

- [ ] Document all conditions used and their purpose
- [ ] Document all recorders used and their purpose
- [ ] Explain trust assumptions to users
- [ ] Provide refund mechanism documentation
- [ ] List supported tokens

### 5. Security Review ✅

- [ ] Code audit by reputable firm
- [ ] Peer review of condition/recorder choices
- [ ] Test coverage > 90%
- [ ] Invariant testing with Echidna/Medusa
- [ ] Scenario-based testing

---

## RELEASE_CONDITION = address(0) Risk

### Warning: Immediate Release Without Escrow Period

When deploying a PaymentOperator with `RELEASE_CONDITION = address(0)`, **anyone can release funds immediately after authorization**. This is the default behavior and is dangerous for most payment use cases.

### Attack Scenario: Front-Running Refund Requests

```
1. Payer authorizes payment (funds enter escrow)
2. Payer realizes an issue and submits requestRefund() to the RefundRequest contract
3. Receiver sees the refund request in the mempool
4. Receiver front-runs with release() (no condition to block it)
5. Funds are captured by receiver before refund can be processed
6. Payer's refund request becomes meaningless (funds already released)
```

This is a **race condition** inherent to `address(0)` release conditions. The RefundRequest contract only tracks request status — it does not prevent releases.

### When address(0) is Acceptable

- **Trusted receiver relationships**: Both parties know and trust each other (e.g., internal treasury transfers)
- **Instant settlement**: Use cases where escrow hold is not needed (e.g., point-of-sale)
- **Charge-only flows**: Using `charge()` instead of `authorize()` (no escrow hold)

### When address(0) is Dangerous

- **Consumer-to-merchant payments**: Consumers expect dispute resolution windows
- **Marketplace escrow**: Buyers need protection against non-delivery
- **Any flow using RefundRequest**: Without escrow period, refund requests are trivially front-runnable

### Recommendation

Use `EscrowPeriod` as `RELEASE_CONDITION` for any payment flow that involves:
- Refund requests (RefundRequest contract)
- Dispute resolution
- Delivery-based settlement

```solidity
// SAFE: Release blocked until escrow period passes
config.releaseCondition = address(escrowPeriod);

// DANGEROUS: Immediate release, refund requests easily front-run
config.releaseCondition = address(0);
```

See [SECURITY.md](./SECURITY.md) for the full escrow trust boundary analysis.

---

## Incident Response

### If Malicious Condition/Recorder Detected

**Operator is immutable** - cannot be upgraded or changed after deployment.

**Immediate actions:**

1. **Alert users** - Publish security advisory
2. **Document behavior** - What operations are affected?
3. **Guide recovery**:
   - Can users refund after `refundExpiry`?
   - Is there an alternative operator?
   - Can a new operator be deployed?
4. **Post-mortem** - Publish analysis and learnings

### Prevention is Critical

Because operators are immutable:
- ✅ Audit BEFORE deployment
- ✅ Test thoroughly
- ✅ Use safe library conditions/recorders
- ✅ Minimize custom logic

---

## Contact

For security concerns:
- Open a security advisory on GitHub
- Review audit reports in `/audits`
- See SECURITY.md for security contacts

**Last Updated**: 2026-01-25
