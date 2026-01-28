# Glossary

Domain-specific terms used in x402r-contracts.

---

## Core Concepts

### Payment Operator
The entry point contract for all payment operations. Each operator is immutable after deployment and encodes specific business logic through its condition and recorder slots. Operators delegate fund custody to the escrow layer.

### AuthCaptureEscrow (Escrow)
The trustless custody contract that holds user funds during the payment lifecycle. Enforces the payment state machine (authorize → release/refund) with reentrancy guards. Operators interact with escrow but cannot bypass its invariants.

### Payment State Machine
The set of valid states and transitions for a payment:
- **NonExistent** → **InEscrow** (via authorize)
- **InEscrow** → **Released** (via release/capture, full amount)
- **InEscrow** → **PartiallyReleased** (via release, partial amount)
- **InEscrow** → **Refunded** (via refundInEscrow, full capturable amount)
- **InEscrow** → **Expired** (authorizationExpiry passes)
- **Expired** → **RefundedPostEscrow** (via refundPostEscrow)

### PaymentInfo
The struct that uniquely identifies a payment. Contains: operator, payer, receiver, token, maxAmount, expiry timestamps, fee bounds, and a salt for uniqueness. The keccak256 hash of this struct is the payment's unique identifier.

### Payment Hash
`keccak256(abi.encode(paymentInfo))` — the canonical identifier for a payment used as the key in all mappings.

---

## Roles

### Payer
The address that funds a payment. Can void authorized payments after `authorizationExpiry`. Can freeze escrow periods (if operator's freeze policy allows). Approves tokens to the collector before authorization.

### Receiver
The address that receives released funds. Can approve or deny refund requests. Has priority access to release operations (via ReceiverCondition). Also referred to as "merchant" in commerce contexts.

### Operator Deployer
The entity that deploys a PaymentOperator with specific conditions, recorders, and fee configuration. Responsible for choosing safe, audited plugins. Cannot modify the operator after deployment.

### Arbiter
An external address (e.g., dispute resolution service) that can approve/deny refund requests when funds are in escrow. Authorized via the operator's `REFUND_IN_ESCROW_CONDITION` slot.

### Protocol Owner
The owner of the `ProtocolFeeConfig` contract. Can queue timelocked changes to the protocol fee calculator and fee recipient. Expected to be a multisig.

---

## Fee System

### Basis Points (BPS)
Fee unit where 1 BPS = 0.01%. Range: 0–10000 (0%–100%). Fees are calculated as `amount * feeBps / 10000`.

### Protocol Fee
Fee charged on every release, accruing to the `protocolFeeRecipient`. Calculated by the `ProtocolFeeConfig`'s fee calculator. Subject to a 7-day timelock for changes.

### Operator Fee
Per-operator immutable fee set at deployment time via `FEE_CALCULATOR`. Accrues to the operator's `FEE_RECIPIENT`. Cannot be changed after deployment.

### Combined Fee
`protocolFeeBps + operatorFeeBps`. Must not exceed the payment's `maxFeeBps` or 10000 BPS total.

### Accumulated Protocol Fees
Protocol fees held in the operator contract's token balance, tracked per-token via `accumulatedProtocolFees[token]`. Distributed to the protocol fee recipient via `distributeFees()`.

### Fee Calculator (IFeeCalculator)
Interface that returns a fee in BPS for a given payment. `StaticFeeCalculator` always returns a fixed value. Custom calculators can implement dynamic pricing.

---

## Condition System

### Condition (ICondition)
A pre-check hook that returns `bool`. Called BEFORE an operation executes. If it returns `false`, the operation reverts with `ConditionNotMet()`. Conditions are `view` functions and should not modify state.

### Condition Slot
One of 5 immutable condition addresses on a PaymentOperator: `AUTHORIZE_CONDITION`, `CHARGE_CONDITION`, `RELEASE_CONDITION`, `REFUND_IN_ESCROW_CONDITION`, `REFUND_POST_ESCROW_CONDITION`. `address(0)` means "allow all" (default).

### Combinator
A condition that composes other conditions using boolean logic:
- **AndCondition**: All child conditions must return `true`
- **OrCondition**: At least one child condition must return `true`
- **NotCondition**: Negates a single child condition

### MAX_CONDITIONS
Hard limit of 10 conditions per combinator, preventing gas griefing from deeply nested condition trees.

---

## Recorder System

### Recorder (IRecorder)
A post-action hook called AFTER the escrow operation completes. Can modify state (unlike conditions). Used for indexing, timestamp tracking, and analytics.

### Recorder Slot
One of 5 immutable recorder addresses on a PaymentOperator: `AUTHORIZE_RECORDER`, `CHARGE_RECORDER`, `RELEASE_RECORDER`, `REFUND_IN_ESCROW_RECORDER`, `REFUND_POST_ESCROW_RECORDER`. `address(0)` means "no-op" (default).

### RecorderCombinator
Composes multiple recorders into a single slot. Calls each sub-recorder sequentially. Limited to `MAX_RECORDERS = 10`.

### BaseRecorder
Abstract base class for recorders. Provides `_verifyAndHash()` which validates the caller is an authorized operator (via codehash or direct address check) and that the payment exists in escrow.

### Codehash Authorization
`BaseRecorder` uses `EXTCODEHASH` to verify that the calling contract's runtime bytecode matches an expected hash. This prevents impersonation by contracts with different code.

---

## Escrow Period System

### Escrow Period
A time window after authorization during which funds are held in escrow before release is permitted. Enforced by `EscrowPeriod` (which implements both `ICondition` and `IRecorder`) as both the `AUTHORIZE_RECORDER` and `RELEASE_CONDITION`.

### EscrowPeriod
Combined recorder and condition contract. Records `block.timestamp` when a payment is authorized (via `AuthorizationTimeRecorder` inheritance), checks `block.timestamp >= authorizedAt + ESCROW_PERIOD` and `!frozen` for release, and provides freeze/unfreeze capabilities.

### Freeze
A mechanism that blocks release during the escrow period. The payer (or authorized party) calls `recorder.freeze(paymentInfo)` to set `frozenUntil = block.timestamp + FREEZE_DURATION`. A frozen payment cannot be released until `frozenUntil` passes or `unfreeze()` is called.

### Freeze Policy (IFreezePolicy)
Configurable policy that determines who can freeze and unfreeze, and for how long. Delegates authorization to `ICondition` contracts. Deployed via `FreezePolicyFactory`.

### Freeze Duration
How long a freeze lasts. `0` means permanent (until explicitly unfrozen). Non-zero values auto-expire.

---

## Refund System

### Refund Request
A formal request from a payer for a refund. Tracked by the `RefundRequest` contract with lifecycle states: `Pending` → `Approved`/`Denied`. Requires receiver or arbiter approval.

### RefundInEscrow
Refund path while funds are still in escrow (capturable > 0). Reduces `capturableAmount` and increases `refundableAmount`. Governed by `REFUND_IN_ESCROW_CONDITION`.

### RefundPostEscrow
Refund path after escrow is released (capturable = 0). Receiver must voluntarily refund from their own balance. Governed by `REFUND_POST_ESCROW_CONDITION`.

### Refund Expiry
Timestamp after which a payer can reclaim authorized but uncaptured funds. Safety valve ensuring funds are never permanently locked.

---

## Deployment

### CREATE2
Deterministic deployment using `CREATE2` opcode. Address is computed from `keccak256(0xff ++ deployer ++ salt ++ keccak256(bytecode))`. All factories use CREATE2 for predictable addresses.

### Factory
Contract that deploys other contracts with deterministic addresses. Factories are idempotent: deploying the same configuration twice returns the same address without redeploying.

### TokenStore
Per-operator token custody address created by the escrow. Each operator gets an isolated token store, preventing cross-operator fund contamination.

---

## Security Terms

### CEI Pattern (Checks-Effects-Interactions)
Ordering discipline for state-modifying functions: (1) validate inputs, (2) update storage and emit events, (3) make external calls. Prevents reentrancy vulnerabilities.

### Reentrancy Guard
Modifier (`nonReentrant`) that prevents a function from being called while it is already executing. The escrow uses Solady's `ReentrancyGuardTransient` (EIP-1153) for gas efficiency.

### Timelock
A delay between proposing and executing a governance change. `ProtocolFeeConfig` uses a 7-day timelock for fee calculator and recipient changes, giving users time to exit.

### Trust Boundary
The line between trustless and trusted components. The escrow is trustless (enforces invariants regardless of caller). The operator is trusted (deployer chooses condition/recorder plugins that users must trust).
