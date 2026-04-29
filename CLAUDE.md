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

- `src/operator/payment/` — PaymentOperator and access control. Action methods: `authorize`, `charge`, `capture`, `void`, `refund` (forward to canonical `AuthCaptureEscrow` methods of the same name)
- `src/operator/PaymentOperatorFactory.sol` — Deterministic CREATE2 factory
- `src/plugins/conditions/` — `ICondition` implementations and And/Or/Not combinators
- `src/plugins/hooks/` — `IHook` implementations (`run()`) and combinator
- `src/plugins/escrow-period/` — EscrowPeriod (merged hook+condition) + factory
- `src/plugins/freeze/` — Freeze condition + factory
- `src/plugins/fees/` — ProtocolFeeConfig, StaticFeeCalculator + factory
- `src/requests/` — Refund request flow

## Fee System

Additive: `totalFee = protocolFee + operatorFee`. Protocol fees use 7-day timelocked calculator swap. Fees locked at `authorize()` in `authorizedFees[hash]` and used at `capture()`. Validated against `paymentInfo.minFeeBps`/`maxFeeBps`.

## Operator Model

Operator stores only `authorizedFees[hash]` and `accumulatedProtocolFees[token]`. Payment state queried from escrow via `ESCROW.paymentState(hash)`. 10 plugin slots: 5 pre-action conditions + 5 post-action hooks (`address(0)` = default).

## Deploy

Single CREATE2 canonical deploy via CreateX guarded salts: `script/DeployCreate2.s.sol`. Both `CANONICAL_OWNER` and `CANONICAL_FEE_RECIPIENT` constants in the script must be set before running. Salt namespaces: `commerce-payments::v1::*` for upstream primitives (vendored unchanged), `x402r-canonical-v1::*` for x402r-authored contracts.
