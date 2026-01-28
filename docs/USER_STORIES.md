# User Stories

Formal user stories for all payment flows in x402r-contracts.

---

## Payment Authorization

### US-1: Authorize a Payment
**As a** payer,
**I want to** authorize a payment to a receiver with a maximum amount,
**so that** funds are held in escrow until the receiver releases or I request a refund.

**Acceptance criteria:**
- Payer pre-approves via `collector.preApprove(paymentInfo)`
- Operator calls `escrow.authorize()` holding up to `maxAmount` tokens
- Payment state transitions from `NonExistent` to `InEscrow`
- `AuthorizationCreated` event is emitted
- If an `AUTHORIZE_CONDITION` is set, it must return `true`
- If an `AUTHORIZE_RECORDER` is set, it is called after authorization

### US-2: Charge (Authorize + Immediate Release)
**As a** receiver in a point-of-sale scenario,
**I want to** charge a payer in a single transaction,
**so that** I receive funds immediately without an escrow hold.

**Acceptance criteria:**
- Payer pre-approves via `collector.preApprove(paymentInfo)`
- Operator calls `escrow.charge()` which authorizes and captures in one step
- Fees are deducted and sent to fee recipients
- Payment state transitions directly to `Released`
- Both `CHARGE_CONDITION` and `CHARGE_RECORDER` are invoked if set

---

## Payment Release

### US-3: Full Release
**As a** receiver (merchant),
**I want to** release the full authorized amount,
**so that** I receive payment minus fees.

**Acceptance criteria:**
- Caller passes the `RELEASE_CONDITION` check (or condition is `address(0)`)
- Full `capturableAmount` is released to receiver
- Protocol fee and operator fee are deducted from the released amount
- `accumulatedProtocolFees[token]` increases by the protocol fee share
- Payment state transitions to `Released`
- `RELEASE_RECORDER` is called if set

### US-4: Partial Release
**As a** receiver,
**I want to** release a portion of the authorized amount,
**so that** I can capture partial payment while leaving the remainder refundable.

**Acceptance criteria:**
- Release amount < `capturableAmount`
- `capturableAmount` decreases by the released amount
- Payment remains in `InEscrow` state
- Multiple partial releases are allowed until `capturableAmount` reaches 0

### US-5: Release After Escrow Period
**As a** receiver using an escrow period,
**I want to** release funds after the escrow period expires,
**so that** the payer had a dispute window before I receive funds.

**Acceptance criteria:**
- `EscrowPeriodCondition.check()` returns `true` (timestamp >= authTime + escrowPeriod)
- Payment is not frozen (`frozenUntil <= block.timestamp`)
- Release proceeds as in US-3/US-4

---

## Refund Flows

### US-6: Refund In Escrow
**As an** operator or arbiter,
**I want to** refund a payment while funds are still in escrow,
**so that** the payer's funds are returned without requiring receiver cooperation.

**Acceptance criteria:**
- `capturableAmount > 0` (funds still in escrow)
- Caller passes `REFUND_IN_ESCROW_CONDITION` (or condition is `address(0)`)
- `capturableAmount` decreases, `refundableAmount` increases
- Payer can later withdraw via escrow's refund mechanism

### US-7: Refund Post Escrow
**As a** receiver,
**I want to** voluntarily refund a payment after I've already received the funds,
**so that** I can resolve a dispute or correct an error.

**Acceptance criteria:**
- `capturableAmount == 0` (all funds released or refunded from escrow)
- Receiver transfers tokens back and calls `refundPostEscrow()`
- `REFUND_POST_ESCROW_CONDITION` is checked if set

### US-8: Request a Refund
**As a** payer,
**I want to** submit a formal refund request with a reason and amount,
**so that** the receiver or arbiter can review and approve/deny it.

**Acceptance criteria:**
- Payer calls `requestRefund(paymentInfo, amount, nonce, reason)`
- Request is stored with `Pending` status
- `RefundRequested` event is emitted with all details
- Nonce prevents duplicate requests
- Amount must be > 0

### US-9: Approve a Refund Request
**As a** receiver or arbiter,
**I want to** approve a pending refund request,
**so that** the payer's refund can proceed.

**Acceptance criteria:**
- Only receiver, or arbiter (via `REFUND_IN_ESCROW_CONDITION` while in escrow) can approve
- Request status transitions from `Pending` to `Approved`
- `RefundStatusUpdated` event is emitted

### US-10: Deny a Refund Request
**As a** receiver or arbiter,
**I want to** deny a pending refund request,
**so that** I can reject invalid or fraudulent claims.

**Acceptance criteria:**
- Same authorization as US-9
- Request status transitions from `Pending` to `Denied`
- `RefundStatusUpdated` event is emitted

### US-11: Reclaim Expired Funds
**As a** payer,
**I want to** reclaim my authorized funds after `authorizationExpiry`,
**so that** my funds are never permanently locked in escrow.

**Acceptance criteria:**
- `block.timestamp > authorizationExpiry`
- Payment state becomes `Expired`
- Payer can call `escrow.refund()` to reclaim funds
- No condition check required for expiry-based refund

---

## Escrow Period & Freeze

### US-12: Freeze a Payment
**As a** payer disputing a transaction,
**I want to** freeze the escrow to prevent release during my dispute,
**so that** the receiver cannot drain funds while I seek resolution.

**Acceptance criteria:**
- Freeze policy's `canFreeze()` returns `true` for the caller
- `frozenUntil` is set to `block.timestamp + FREEZE_DURATION`
- Release is blocked until freeze expires or is explicitly unfrozen
- `PaymentFrozen` event is emitted
- Can only freeze during escrow period (before `authTime + ESCROW_PERIOD`)

### US-13: Unfreeze a Payment
**As a** payer or arbiter who has resolved a dispute,
**I want to** unfreeze a payment,
**so that** the receiver can proceed with release.

**Acceptance criteria:**
- Freeze policy's `canUnfreeze()` returns `true` for the caller
- `frozenUntil` is set to 0
- Release is unblocked
- `PaymentUnfrozen` event is emitted

---

## Fee Management

### US-14: Distribute Protocol Fees
**As a** protocol operator,
**I want to** distribute accumulated protocol fees to the fee recipient,
**so that** fees flow to the protocol treasury.

**Acceptance criteria:**
- `accumulatedProtocolFees[token] > 0`
- Protocol share is transferred to `protocolFeeRecipient`
- Operator share is transferred to `FEE_RECIPIENT`
- `FeesDistributed` event is emitted
- `accumulatedProtocolFees[token]` is reset to 0

### US-15: Change Protocol Fee Calculator (Timelocked)
**As a** protocol owner (multisig),
**I want to** update the fee calculator with a 7-day timelock,
**so that** users have time to exit before fee changes take effect.

**Acceptance criteria:**
- Owner calls `queueCalculatorChange(newCalculator)`
- After 7 days, owner calls `executeCalculatorChange()`
- New calculator takes effect for all future operations
- `CalculatorChangeQueued` and `CalculatorChangeExecuted` events are emitted
- Owner can cancel with `cancelCalculatorChange()` before execution

### US-16: Change Protocol Fee Recipient (Timelocked)
**As a** protocol owner,
**I want to** update the fee recipient address with a 7-day timelock,
**so that** protocol revenue flows to the correct treasury.

**Acceptance criteria:**
- Same 7-day timelock as US-15
- `RecipientChangeQueued` and `RecipientChangeExecuted` events are emitted

---

## Deployment & Factory

### US-17: Deploy a Payment Operator
**As a** service provider,
**I want to** deploy a PaymentOperator with custom conditions and recorders,
**so that** I can offer payment services with my specific business logic.

**Acceptance criteria:**
- Call `factory.deployOperator(config)` with desired condition/recorder configuration
- Operator is deployed with deterministic CREATE2 address
- All condition and recorder slots are immutable after deployment
- `OperatorDeployed` event is emitted

### US-18: Deploy Escrow Period Infrastructure
**As a** service provider requiring dispute windows,
**I want to** deploy an escrow period condition + recorder pair,
**so that** I can configure my operator with a release delay.

**Acceptance criteria:**
- Call `EscrowPeriodConditionFactory.deploy(escrowPeriod, freezePolicy, codehash)`
- Both recorder and condition are deployed with deterministic addresses
- Idempotent: calling again with same params returns existing addresses

### US-19: Predict Deployment Address
**As a** deployer planning multi-contract setups,
**I want to** predict the address of a contract before deploying it,
**so that** I can configure cross-references in a single batch.

**Acceptance criteria:**
- Call `factory.computeAddress(params)` or `factory.computeAddresses(params)`
- Returned address matches the actual deployed address
- Works for all factories: PaymentOperatorFactory, StaticFeeCalculatorFactory, EscrowPeriodConditionFactory, FreezePolicyFactory

---

## Querying & Indexing

### US-20: Query Payer's Payment History
**As a** payer or frontend application,
**I want to** retrieve a paginated list of my payments,
**so that** I can display transaction history.

**Acceptance criteria:**
- Call `indexRecorder.getPayerPayments(payer, offset, count)`
- Returns `PaymentRecord[]` with hash, amount, and record index
- Pagination works correctly (offset, count, total)

### US-21: Query Receiver's Payment History
**As a** receiver or analytics dashboard,
**I want to** retrieve all payments received,
**so that** I can reconcile incoming payments.

**Acceptance criteria:**
- Call `indexRecorder.getReceiverPayments(receiver, offset, count)`
- Same pagination behavior as US-20
