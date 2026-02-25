# x402r-contracts

Solidity smart contracts for x402r. Built with Foundry.

## Commands

```bash
forge build
forge test -vvv
forge fmt              # Format — run before every commit
forge fmt --check      # CI formatting check
```

## License

All files in `src/` and `script/` must use `// SPDX-License-Identifier: BUSL-1.1`.

## Code Standards

- **CEI Pattern** (Checks-Effects-Interactions) in all state-modifying functions: validate → update storage/emit events → external calls
- Zero `note[...]` lines in `forge build` output — fix unused imports, wrap modifier logic

## Architecture

- `src/operator/payment/` — PaymentOperator and access control
- `src/operator/PaymentOperatorFactory.sol` — Deterministic CREATE2 factory
- `src/plugins/conditions/` — ICondition implementations and And/Or/Not combinators
- `src/plugins/recorders/` — IRecorder implementations and combinator
- `src/plugins/escrow-period/` — EscrowPeriod (merged recorder+condition) + factory
- `src/plugins/freeze/` — Freeze condition + factory
- `src/plugins/fees/` — ProtocolFeeConfig, StaticFeeCalculator + factory
- `src/requests/` — Refund request flow

## Fee System

Additive: `totalFee = protocolFee + operatorFee`. Protocol fees use 7-day timelocked calculator swap. Fees locked at `authorize()` in `authorizedFees[hash]` and used at `release()`. Validated against `paymentInfo.minFeeBps`/`maxFeeBps`.

## Operator Model

Operator stores only `authorizedFees[hash]` and `accumulatedProtocolFees[token]`. Payment state queried from escrow via `ESCROW.paymentState(hash)`. 10 plugin slots: 5 conditions + 5 recorders (`address(0)` = default).
