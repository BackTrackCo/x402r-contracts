# Compiler & Platform Notes

Documentation of compiler optimization choices, EIP-1153 requirements, and potential risks.

---

## Compiler Configuration

From `foundry.toml`:

```toml
solc = "0.8.33"
optimizer = true
optimizer_runs = 200
via_ir = true
evm_version = "cancun"
```

---

## 1. via-IR Optimization

### What It Does

`via_ir = true` enables Solidity's Yul-based intermediate representation (IR) pipeline. Instead of the legacy codegen path, the compiler:

1. Lowers Solidity to Yul IR
2. Applies Yul-level optimizations (inlining, common subexpression elimination, dead code elimination, stack-to-memory moves)
3. Generates EVM bytecode from optimized Yul

### Why We Use It

- **Stack depth**: Complex functions with many local variables hit the EVM's 16-slot stack limit under legacy codegen. via-IR automatically spills variables to memory, avoiding "Stack too deep" errors.
- **Better optimization**: Cross-function inlining and global optimization produce smaller, cheaper bytecode for complex contracts.
- **Required by Solady**: Some Solady patterns assume via-IR for optimal gas behavior.

### Risks

1. **Dead code elimination**: The optimizer may remove code it determines is unreachable. In theory, this could eliminate security checks if the optimizer incorrectly proves them redundant. **Mitigation**: All security-critical checks are tested via the full test suite, which runs against compiled bytecode.

2. **Memory layout changes**: via-IR may change how variables are laid out in memory compared to legacy codegen. This is transparent to Solidity code but could affect inline assembly. **Mitigation**: No inline assembly in x402r source code. Solady's assembly is tested independently.

3. **Compilation time**: via-IR is significantly slower than legacy codegen. **Mitigation**: Acceptable tradeoff for deployment artifacts. Development uses cached builds.

4. **Optimizer bugs**: The Yul optimizer has had bugs in past Solidity versions (e.g., optimizer sequence issues in 0.8.13-0.8.17). **Mitigation**: Using Solidity 0.8.33, which has years of via-IR maturity and fixes.

### Verification

- All 176 tests pass against via-IR compiled bytecode
- Fuzz and invariant tests exercise compiled code, not source analysis
- Deploy scripts use the same compiler settings as tests

---

## 2. Optimizer Runs

### Configuration

`optimizer_runs = 200` balances deployment cost vs runtime cost.

- **Low runs (1-200)**: Optimizer favors smaller bytecode (cheaper deployment)
- **High runs (1000+)**: Optimizer favors cheaper execution (smaller per-call cost)
- **200**: Standard choice for contracts called moderately often

### Impact

For x402r contracts, the primary gas-sensitive operations are:
- `authorize()` / `charge()`: called per payment
- `release()`: called per settlement
- `distributeFees()`: called periodically

200 runs is appropriate since these contracts are called regularly but not at DeFi-level frequency.

---

## 3. EIP-1153: Transient Storage

### What It Is

EIP-1153 introduces two new opcodes: `TSTORE` and `TLOAD`. Transient storage is:
- Automatically cleared at the end of each transaction
- Much cheaper than regular storage (100 gas vs 20000 gas for first write)
- Available since the **Cancun** hard fork (March 2024)

### How We Use It

Solady's `ReentrancyGuardTransient` uses transient storage for the reentrancy lock:

```solidity
// Solady: ReentrancyGuardTransient
// Uses TSTORE/TLOAD instead of SSTORE/SLOAD for the lock flag
modifier nonReentrant() {
    // TLOAD slot → check not locked
    // TSTORE slot → set locked
    _;
    // TSTORE slot → clear locked (automatic at tx end anyway)
}
```

This is used by `AuthCaptureEscrow` (in the `commerce-payments` dependency).

### Chain Compatibility

EIP-1153 requires the **Cancun** EVM version. Supported chains:

| Chain | Cancun Support | Status |
|-------|---------------|--------|
| Ethereum Mainnet | Yes (March 2024) | Supported |
| Base | Yes | Supported |
| Optimism | Yes | Supported |
| Arbitrum | Yes | Supported |
| Polygon zkEVM | Yes | Supported |
| Avalanche C-Chain | Yes | Supported |
| BNB Smart Chain | Yes (June 2024) | Supported |
| Fantom | No | NOT SUPPORTED |
| Celo | Partial | Verify before deployment |
| zkSync Era | No (different EVM) | NOT SUPPORTED |
| Linea | Verify | Test before deployment |

### Deployment Requirement

**Before deploying to any chain:**

1. Verify the chain supports EVM version `cancun` (EIP-1153, EIP-4844, EIP-4788, EIP-5656, EIP-6780, EIP-7516)
2. Test the full suite on a fork of the target chain
3. Verify `TSTORE`/`TLOAD` opcodes don't revert

If deploying to a chain without Cancun support, the escrow dependency must be rebuilt with `ReentrancyGuard` (regular storage) instead of `ReentrancyGuardTransient`.

---

## 4. EVM Version: Cancun

### Configuration

`evm_version = "cancun"` in `foundry.toml`.

### Opcodes Used

Beyond EIP-1153, the Cancun EVM version enables:

| EIP | Opcode/Feature | Used By |
|-----|---------------|---------|
| EIP-1153 | `TSTORE`, `TLOAD` | ReentrancyGuardTransient (Solady) |
| EIP-4844 | `BLOBHASH`, `BLOBBASEFEE` | Not used |
| EIP-4788 | Beacon block root | Not used |
| EIP-5656 | `MCOPY` | Compiler may use for memory copies |
| EIP-6780 | `SELFDESTRUCT` restriction | Not used (no selfdestruct) |
| EIP-7516 | `BLOBBASEFEE` opcode | Not used |

Only EIP-1153 and potentially EIP-5656 are relevant to this codebase. EIP-5656 (`MCOPY`) may be emitted by the Solidity compiler for efficient memory operations but is transparent to the source code.

---

## 5. Solidity 0.8.33 Specifics

### Checked Arithmetic

All arithmetic operations in Solidity 0.8+ include automatic overflow/underflow checks. No `unchecked` blocks are used in x402r source code. This means:

- Integer overflow reverts (e.g., `uint120.max + 1` reverts)
- Integer underflow reverts (e.g., `0 - 1` reverts)
- Division by zero reverts

### Custom Errors

All revert reasons use custom errors (gas-efficient, introduced in 0.8.4):
```solidity
error ConditionNotMet();
error InvalidOperator();
error FeeTooHigh();
```

### ABI Coder v2

Default in 0.8+. Supports nested structs, dynamic arrays in function signatures. Used extensively for `PaymentInfo` struct passing.

---

## 6. Dependency Compiler Notes

### Solady (Assembly)

Solady uses hand-optimized Yul/inline assembly for gas efficiency:
- `SafeTransferLib`: Assembly-based ERC20 transfer wrappers
- `ReentrancyGuardTransient`: Assembly TSTORE/TLOAD
- `Ownable`: Assembly-optimized ownership

**Audit status**: Solady is audited and battle-tested (used by Uniswap, Coinbase). See [Solady audit reports](https://github.com/vectorized/solady/tree/main/audits).

### OpenZeppelin Contracts

Standard Solidity implementations (no assembly in most contracts). Used for:
- `SafeERC20`: Safe ERC20 transfer wrappers (used by escrow dependency)
- `IERC20`: Interface definitions

### commerce-payments (AuthCaptureEscrow)

The escrow dependency uses:
- Solady `ReentrancyGuardTransient` (EIP-1153)
- OpenZeppelin `SafeERC20`
- Standard Solidity patterns

---

## 7. Recommendations

1. **Before deploying to a new chain**: Run `forge test --fork-url <CHAIN_RPC>` to verify all opcodes work correctly.

2. **When upgrading Solidity**: Re-run the full test suite including fuzz and invariant tests. Check the Solidity changelog for optimizer bug fixes.

3. **When upgrading Solady**: Run differential fuzz tests (`test/fuzz/DifferentialSafeTransfer.t.sol`) to verify behavior consistency.

4. **For chains without Cancun**: Fork the escrow dependency and replace `ReentrancyGuardTransient` with `ReentrancyGuard`. Update `evm_version` in `foundry.toml`.
