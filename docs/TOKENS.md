# Token Compatibility Guide

## Overview

The x402r-contracts payment escrow system (PaymentOperator + AuthCaptureEscrow) is designed to work with **standard ERC20 tokens** while maintaining strict accounting integrity. This document outlines which token types are supported and which are explicitly excluded.

## ✅ Supported Token Types

The following token patterns are **fully supported** and tested:

### Standard ERC20 Tokens
- **Examples**: WETH, LINK, UNI, AAVE
- **Status**: ✅ Fully supported
- **Notes**: Standard compliant tokens work perfectly

### Missing Return Value Tokens
- **Examples**: USDT, BNB, OMG
- **Status**: ✅ Fully supported
- **Implementation**: Uses OpenZeppelin SafeERC20 wrapper
- **Notes**: Tokens that don't return `bool` on transfer/transferFrom are handled correctly

### Pausable Tokens
- **Examples**: BNB, ZIL
- **Status**: ✅ Supported (will revert when paused)
- **Notes**: Operations will fail naturally when token is paused. This is expected behavior.

### Tokens with Blocklists
- **Examples**: USDC, USDT (OFAC compliance)
- **Status**: ✅ Supported (will revert for blocked addresses)
- **Notes**: Transfers to/from blocked addresses will fail naturally. Operators should be aware of this risk.

### Upgradeable Tokens
- **Examples**: USDC, USDT (TransparentUpgradeableProxy)
- **Status**: ✅ Supported with caveats
- **Risks**:
  - Admin could upgrade token logic mid-operation
  - Could introduce fees or rebasing after upgrade
- **Mitigation**: Protocol doesn't cache token behavior, adapts to upgrades
- **Recommendation**: Be aware of centralization risk with admin-controlled tokens

### Low/High Decimal Tokens
- **Examples**:
  - Low: USDC (6 decimals), GUSD (2 decimals)
  - High: YAM-V2 (24 decimals)
- **Status**: ✅ Fully supported
- **Notes**: Protocol is decimal-agnostic, works with any decimal count

### Tokens with Approval Race Conditions
- **Examples**: USDT, KNC
- **Status**: ✅ Safe
- **Notes**: Users approve TokenCollector contracts directly, not affected by race conditions

### Tokens that Revert on Zero Transfers/Approvals
- **Examples**: Various tokens
- **Status**: ✅ Compatible
- **Notes**: Protocol doesn't make zero-value transfers

### Tokens with Non-String Metadata
- **Examples**: MKR (bytes32 metadata)
- **Status**: ✅ Compatible
- **Notes**: Protocol doesn't query token metadata

### Tokens with Large Approval Restrictions
- **Examples**: UNI (max 2^96), COMP
- **Status**: ✅ Compatible
- **Notes**: Handled by TokenCollector approval logic

---

## ❌ Unsupported Token Types

The following token patterns are **explicitly NOT supported** by design. The protocol will **reject** these tokens to maintain accounting integrity.

### 1. Fee-on-Transfer Tokens ❌ CRITICAL

- **Examples**: STA, PAXG, cUSDCv3, SAFEMOON
- **Status**: ❌ NOT SUPPORTED
- **Why Rejected**: Protocol enforces strict balance verification
- **Behavior**: Transactions will **revert with `TokenCollectionFailed()`**

**Code Evidence**:
```solidity
// AuthCaptureEscrow.sol:456-462
function _collectTokens(...) internal {
    uint256 tokenStoreBalanceBefore = IERC20(token).balanceOf(tokenStore);
    TokenCollector(tokenCollector).collectTokens(paymentInfo, tokenStore, amount, collectorData);
    uint256 tokenStoreBalanceAfter = IERC20(token).balanceOf(tokenStore);
    // This check will ALWAYS fail for fee-on-transfer tokens
    if (tokenStoreBalanceAfter != tokenStoreBalanceBefore + amount) revert TokenCollectionFailed();
}
```

**Why This Design Choice**:
- Prevents accounting errors where user is charged X but protocol receives X-fee
- Maintains exact payment amounts for commerce use cases
- Security-first approach prioritizing correctness

**Workaround**: Wrap fee-on-transfer tokens in a standard ERC20 wrapper before use

---

### 2. Rebasing Tokens ❌ HIGH RISK

- **Examples**: AMPL (Ampleforth), stETH (Lido Staked ETH), RAI
- **Status**: ❌ NOT SUPPORTED
- **Why Rejected**: Balance changes break accounting invariants
- **Behavior**: Accounting corruption, incorrect refunds/releases

**Problem**:
```solidity
// Protocol stores fixed amounts:
paymentState[hash] = PaymentState({
    hasCollectedPayment: true,
    capturableAmount: uint120(1000),  // Fixed value
    refundableAmount: 0
});

// But rebasing token balance changes:
// Day 1: 1000 stETH in escrow
// Day 2: 1001 stETH in escrow (positive rebase)
// Protocol still thinks it has 1000, accounting is now wrong!
```

**Workaround**: Use wrapped versions (wstETH instead of stETH)

---

### 3. Yield-Bearing Tokens ❌ HIGH RISK

- **Examples**: aDAI (Aave), cUSDC (Compound), staked tokens
- **Status**: ❌ NOT SUPPORTED
- **Why Rejected**: Balance increases over time, breaks accounting
- **Behavior**: Similar to rebasing - accounting corruption

**Problem**: Same as rebasing tokens - protocol assumes fixed balances

**Workaround**: Redeem yield-bearing tokens to underlying before use

---

### 4. Flash Mintable Tokens ⚠️ MEDIUM RISK

- **Examples**: DAI (MakerDAO), RAI
- **Status**: ⚠️ Use with caution
- **Risk**: Flash mint could temporarily inflate supply mid-operation
- **Mitigation**: Reentrancy guards prevent exploitation
- **Recommendation**: Acceptable for most use cases, but be aware of risk

---

### 5. ERC777 Tokens (with hooks) ⚠️ HANDLED

- **Examples**: ERC777 implementations
- **Status**: ⚠️ Supported but risky
- **Protection**: ReentrancyGuardTransient at escrow level
- **Risk**: Malicious hooks could attempt reentrancy
- **Mitigation**: All critical functions use `nonReentrant` modifier
- **Recommendation**: Use standard ERC20 when possible

---

## Token Integration Safety Features

### 1. SafeERC20 Usage ✅

All token transfers use OpenZeppelin's SafeERC20 library:

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;

// All transfers use safe methods:
IERC20(token).safeTransferFrom(from, to, amount);
```

**Benefits**:
- Handles missing return values (USDT, BNB)
- Reverts on failure instead of returning false
- Gas-efficient for standard tokens

---

### 2. Strict Balance Verification ✅

Every token collection is verified:

```solidity
uint256 balanceBefore = IERC20(token).balanceOf(tokenStore);
TokenCollector(tokenCollector).collectTokens(...);
uint256 balanceAfter = IERC20(token).balanceOf(tokenStore);
if (balanceAfter != balanceBefore + amount) revert TokenCollectionFailed();
```

**Benefits**:
- Guarantees exact amount received
- Prevents fee-on-transfer accounting errors
- Detects token implementation bugs

---

### 3. Reentrancy Protection ✅

Uses Solady's gas-optimized ReentrancyGuardTransient:

```solidity
contract AuthCaptureEscrow is ReentrancyGuardTransient {
    function authorize(...) external nonReentrant { ... }
    function charge(...) external nonReentrant { ... }
    function capture(...) external nonReentrant { ... }
    function refund(...) external nonReentrant { ... }
}
```

**Benefits**:
- Protects against ERC777 hook reentrancy
- Gas-optimized using transient storage (EIP-1153)
- Prevents double-spend attacks

---

## Recommended Token List

### Tier 1: Fully Tested & Recommended ✅
- **USDC** (Circle USD Coin) - 6 decimals, pausable, blocklist
- **USDT** (Tether USD) - 6 decimals, missing returns, pausable, blocklist
- **DAI** (MakerDAO) - 18 decimals, flash mintable
- **WETH** (Wrapped Ether) - 18 decimals, standard
- **WBTC** (Wrapped Bitcoin) - 8 decimals, pausable

### Tier 2: Compatible but Use with Caution ⚠️
- **UNI** (Uniswap) - Large approval restrictions
- **COMP** (Compound) - Large approval restrictions
- **LINK** (Chainlink) - Standard but verify on your chain

### Tier 3: DO NOT USE ❌
- **STA** (Statera) - Fee on transfer
- **PAXG** (Paxos Gold) - Fee on transfer
- **AMPL** (Ampleforth) - Rebasing
- **stETH** (Lido Staked ETH) - Rebasing
- **aTokens** (Aave) - Yield-bearing
- **cTokens** (Compound) - Yield-bearing

---

## Testing Token Compatibility

Before using a new token, verify:

1. **Check for fees**:
   ```solidity
   uint256 balanceBefore = token.balanceOf(receiver);
   token.transfer(receiver, 1000);
   uint256 balanceAfter = token.balanceOf(receiver);
   assert(balanceAfter == balanceBefore + 1000); // Should be exact
   ```

2. **Check for rebasing**:
   - Read token documentation
   - Check if balance changes without transfers
   - Look for `rebase()` functions

3. **Check for yield**:
   - Read token documentation
   - Check if it's a wrapper for a DeFi protocol
   - Look for `redeemUnderlying()` functions

4. **Test with test cases**:
   ```bash
   forge test --match-contract TokenCompatibilityTest
   ```

---

## Integration Guide for Developers

### Adding Support for a New Token

1. **Verify token type** (see checklist above)
2. **Run test suite** with the token address
3. **Document in allowlist** if using restricted list
4. **Monitor for upgrades** if token is upgradeable
5. **Test edge cases** (pause, blocklist, zero amounts)

### Example: Adding USDC Support

```solidity
// 1. Verify USDC is standard ERC20 (with pausable + blocklist)
// 2. Test authorization
vm.prank(payer);
collector.preApprove(paymentInfo);
operator.authorize(paymentInfo, 1000e6, address(collector), ""); // Note: 6 decimals

// 3. Handle potential pauses
try operator.release(paymentInfo, 1000e6) {
    // Success
} catch {
    // Could be paused or sender is blocklisted
}
```

---

## FAQ

### Q: Why don't you support fee-on-transfer tokens?

**A**: We prioritize accounting correctness. Fee-on-transfer tokens create a mismatch between charged amount and received amount, which breaks payment integrity. For commerce use cases, users expect to pay exactly what merchants receive.

### Q: Can I wrap fee-on-transfer tokens?

**A**: Yes! Create a standard ERC20 wrapper that absorbs the fee and presents a standard interface. The wrapper would handle the fee logic internally.

### Q: What about tokens that add fees in the future?

**A**: If a token upgrades to add fees, the protocol will start rejecting it. This is intentional - we don't want to process payments with unexpected fee deductions.

### Q: Are stablecoins safe?

**A**: Major stablecoins (USDC, USDT, DAI) are tested and recommended. However, be aware:
- USDC/USDT can pause and blocklist
- DAI is flash mintable
- All are upgradeable (centralization risk)

### Q: What about L2s and alternative chains?

**A**: Token behavior may differ on L2s. Always test on the specific chain you're deploying to. Native currency representations (like Celo's native USDC) may have different behavior.

---

## Security Considerations

### Operator Responsibilities

When deploying a PaymentOperator, ensure:

1. **Only use trusted recorders** - Malicious recorders can reenter during callbacks
2. **Only use trusted conditions** - Malicious conditions can block operations
3. **Verify token compatibility** - Test with actual token before production
4. **Monitor token upgrades** - Upgradeable tokens could change behavior
5. **Handle pauses/blocklists** - Operations may fail for compliant tokens

### User Responsibilities

When making payments:

1. **Verify token is supported** - Check this document
2. **Check token state** - Ensure not paused
3. **Verify not blocklisted** - USDC/USDT compliance checks
4. **Use adequate approvals** - TokenCollector needs approval
5. **Monitor authorizations** - Can be voided or expire

---

## Audit Trail

This token compatibility analysis is based on:
- Trail of Bits Token Integration Checklist
- Trail of Bits Weird ERC20 Database
- OpenZeppelin security best practices
- Comprehensive codebase analysis (2026-01-25)

**Audit Reports**:
- Spearbit (2 audits)
- Coinbase Protocol Security (3 audits)

---

## Contact

For questions about token compatibility:
- Open an issue on GitHub
- Review audit reports in `/audits`
- Check SECURITY.md for security contacts

**Last Updated**: 2026-01-25
