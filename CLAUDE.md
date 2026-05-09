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

Single-stage CREATE2 canonical deploy via CreateX permissionless salts. The upstream `base/commerce-payments@v1.0.0` primitives (`AuthCaptureEscrow`, `ERC3009PaymentCollector`, `Permit2PaymentCollector`) are deployed by Base at canonical addresses on Base mainnet + Base Sepolia (see the upstream README); x402r does not redeploy them.

- `script/DeployX402r.s.sol` — x402r-authored contracts (BUSL): operator factory, plugins, refund-side, hook singletons. Asserts the canonical Base `AuthCaptureEscrow` (`BASE_AUTH_CAPTURE_ESCROW` constant) has code on the target chain before broadcasting. Reads `OWNER_ADDRESS` and `PROTOCOL_FEE_RECIPIENT` from env (alongside `PRIVATE_KEY`); both are baked immutably into `ProtocolFeeConfig` and so move that canonical address. Idempotent — `_deploy2` skips any contract whose predicted address already has code, so partial broadcasts resume cleanly and adding a new singleton to the namespace doesn't require chain-state branching.

Two salt namespaces:
- `x402r-canonical-v1::*` — escrow-independent contracts (`ProtocolFeeConfig`, condition singletons, ctor-arg-free factories, `RefundRequestEvidenceFactory`). Stable across the v1 deployments tracked in `deployments/canonical.json`.
- `x402r-canonical-v1.0.1::*` — escrow-dependent contracts (`PaymentOperatorFactory`, `EscrowPeriodFactory`, `FreezeFactory`, `RefundRequestFactory`, `ReceiverRefundCollector`, `PaymentIndexRecorderHook`). Same source as v1, rebound to the canonical Base escrow. Deployable only on chains where the canonical Base escrow exists (today: Base mainnet + Base Sepolia).

Cross-check before deploying: `forge script script/PredictAddresses.s.sol -vvv` (or `make predict`) recomputes every canonical address and prints the initCodeHashes — addresses must match across machines or the toolchain has drifted.
