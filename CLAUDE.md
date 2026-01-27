# x402r-contracts

Solidity smart contracts for x402r payment protocol. Built with Foundry.

## Build & Test

```bash
forge build
forge test
forge fmt --check
```

## Code Standards

- **CEI Pattern (Checks-Effects-Interactions)**: All state-modifying functions MUST follow CEI ordering:
  1. **Checks** — validate inputs, check conditions, revert on failure
  2. **Effects** — update storage, emit events
  3. **Interactions** — external calls (escrow, recorders, token transfers)

  This prevents reentrancy vulnerabilities. Verify CEI ordering when writing or reviewing any function that makes external calls.

- **Formatting**: Run `forge fmt` before every commit. Verify with `forge fmt --check` — CI will reject unformatted code.

## Architecture

- `src/operator/payment/` — PaymentOperator and access control
- `src/operator/PaymentOperatorFactory.sol` — Deterministic CREATE2 factory
- `src/fees/` — Modular fee system (ProtocolFeeConfig, IFeeCalculator, StaticFeeCalculator)
- `src/conditions/` — Pluggable condition/recorder system (ICondition, IRecorder, combinators)
- `src/requests/` — Refund request flow
- `script/` — Deployment scripts (testnet and production)

## Fee System

Additive modular fees: `totalFee = protocolFee + operatorFee`

- Protocol fees: shared `ProtocolFeeConfig` with 7-day timelocked calculator swap (owned by multisig)
- Operator fees: per-operator immutable `IFeeCalculator` set at deploy time
- Fee recipients: `protocolFeeRecipient` on ProtocolFeeConfig, `FEE_RECIPIENT` on operator
- Protocol fees tracked per-token via `accumulatedProtocolFees` mapping for accurate distribution

## Condition Combinator Pattern

Operators have 10 slots: 5 conditions (before checks) + 5 recorders (after state updates). `address(0)` = default behavior (allow for conditions, no-op for recorders). Conditions can be composed using And/Or/Not combinators.
