# x402r-contracts

Solidity smart contracts for x402r payment protocol. Built with Foundry.

## Build & Test

```bash
forge build
forge test
forge fmt --check
```

## Pre-Commit Checklist

Run all of these before committing. CI will reject failures.

```bash
forge fmt                # Format all files
forge fmt --check        # Verify formatting (CI runs this)
forge build --sizes      # Build with contract size report
forge test -vvv          # Run all tests (CI runs this)
forge build 2>&1 | grep "^note\["  # Check for lint notes (should be empty)
```

## Pre-Deploy Checklist

Before deploying contracts to any network:

```bash
# 1. All CI checks must pass
forge fmt --check
forge build --sizes
forge test -vvv

# 2. No lint notes
forge build 2>&1 | grep "^note\[" && echo "FAIL: fix lint notes" || echo "OK"

# 3. Verify .env has required variables
source .env
# Required: PRIVATE_KEY, ETHERSCAN_API_KEY
# Per-script: ESCROW_ADDRESS, OWNER_ADDRESS, PROTOCOL_FEE_RECIPIENT, etc.

# 4. Dry-run deployment (no broadcast)
forge script script/<Script>.s.sol --rpc-url <RPC_URL> -vvvv

# 5. Deploy with broadcast + verification
forge script script/<Script>.s.sol --rpc-url <RPC_URL> --broadcast --verify -vvvv
```

## Code Standards

- **CEI Pattern (Checks-Effects-Interactions)**: All state-modifying functions MUST follow CEI ordering:
  1. **Checks** — validate inputs, check conditions, revert on failure
  2. **Effects** — update storage, emit events
  3. **Interactions** — external calls (escrow, recorders, token transfers)

  This prevents reentrancy vulnerabilities. Verify CEI ordering when writing or reviewing any function that makes external calls.

- **Formatting**: Run `forge fmt` before every commit. Verify with `forge fmt --check` — CI will reject unformatted code.

- **Lint**: `foundry.toml` configures `[lint]` with `exclude_lints` for convention-conflicting rules. `forge build` output should show zero `note[...]` lines. Fix unused imports and wrap modifier logic rather than suppressing.

## Architecture

- `src/operator/payment/` — PaymentOperator and access control
- `src/operator/PaymentOperatorFactory.sol` — Deterministic CREATE2 factory
- `src/plugins/` — All pluggable modules:
  - `plugins/conditions/` — ICondition, access conditions (PayerCondition, ReceiverCondition, StaticAddressCondition, AlwaysTrueCondition), combinators (And/Or/Not)
  - `plugins/recorders/` — IRecorder, BaseRecorder, AuthorizationTimeRecorder, PaymentIndexRecorder, RecorderCombinator
  - `plugins/escrow-period/` — EscrowPeriod (merged recorder+condition), EscrowPeriodFactory, freeze-policy (FreezePolicy, FreezePolicyFactory, IFreezePolicy)
  - `plugins/fees/` — ProtocolFeeConfig, IFeeCalculator, StaticFeeCalculator, StaticFeeCalculatorFactory
- `src/requests/` — Refund request flow
- `script/` — Deployment scripts (testnet and production)

## Fee System

Additive modular fees: `totalFee = protocolFee + operatorFee`

- Protocol fees: shared `ProtocolFeeConfig` with 7-day timelocked calculator swap (owned by multisig)
- Operator fees: per-operator immutable `IFeeCalculator` set at deploy time
- Fee recipients: `protocolFeeRecipient` on ProtocolFeeConfig, `FEE_RECIPIENT` on operator
- Protocol fees tracked per-token via `accumulatedProtocolFees` mapping for accurate distribution

### Fee Validation & Locking

- **Fee bounds validation**: At `authorize()` and `charge()`, calculated fees are validated against `paymentInfo.minFeeBps` and `paymentInfo.maxFeeBps`. Reverts with `FeeBoundsIncompatible` if fees fall outside payer's accepted range.
- **Fee locking**: Fees are stored at authorization time in `authorizedFees[hash]` and used at `release()`. This prevents protocol fee changes (via timelocked swap) from breaking capture of already-authorized payments.

## Minimal Operator State

The operator stores only fee-related state:
- `authorizedFees[hash]` — fee rates locked at authorization (for release)
- `accumulatedProtocolFees[token]` — protocol fees pending distribution

Payment state (existence, capturable/refundable amounts) is queried directly from the escrow via `ESCROW.paymentState(hash)`. The operator does not duplicate this state.

## Condition Combinator Pattern

Operators have 10 slots: 5 conditions (before checks) + 5 recorders (after state updates). `address(0)` = default behavior (allow for conditions, no-op for recorders). Conditions can be composed using And/Or/Not combinators.
