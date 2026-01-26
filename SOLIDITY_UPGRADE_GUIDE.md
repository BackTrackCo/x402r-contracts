# Solidity Upgrade Guide

## Overview

This guide explains how to safely upgrade the Solidity compiler version for x402r-contracts. Solidity updates often include gas optimizations, bug fixes, and new language features.

---

## Automated Monitoring

### Weekly Checks

The project automatically checks for new Solidity releases every Monday at 9 AM UTC via GitHub Actions workflow: `.github/workflows/solidity-updates.yml`

**What it does**:
1. ✅ Checks for new Solidity releases
2. ✅ Creates GitHub issue if update available
3. ✅ Automatically benchmarks new version
4. ✅ Compares gas costs
5. ✅ Posts results to issue

**You'll receive**:
- GitHub issue with update details
- Gas comparison report
- Test results
- Action items checklist

---

## Manual Upgrade Process

### Step 1: Review Release Notes

When a new version is available, review the official release notes:

**Resources**:
- [Solidity Releases](https://github.com/ethereum/solidity/releases)
- [Solidity Blog](https://blog.soliditylang.org/)
- [Breaking Changes](https://docs.soliditylang.org/en/latest/080-breaking-changes.html)

**Look for**:
- 🔴 Breaking changes
- ⚡ Gas optimizations
- 🐛 Bug fixes
- 🆕 New features

---

### Step 2: Update Compiler Version

Edit `foundry.toml`:

```toml
[profile.default]
solc = "0.8.34"  # Update version here
```

**Version format**: Use exact version (e.g., `0.8.34`, not `^0.8.0`)

---

### Step 3: Run Full Test Suite

```bash
# Clean build artifacts
forge clean

# Rebuild with new compiler
forge build

# Run all tests
forge test -vvv

# Check for compilation warnings
forge build 2>&1 | grep -i "warning"
```

**Expected**: All 32 tests passing, no critical warnings

**If tests fail**:
- Review error messages carefully
- Check for breaking changes in release notes
- May need to update code for compatibility

---

### Step 4: Gas Benchmark

```bash
# Generate baseline (if not already done)
forge snapshot --snap .gas-snapshot-old

# Generate new snapshot
forge snapshot --snap .gas-snapshot-new

# Compare
forge snapshot --diff .gas-snapshot-old .gas-snapshot-new
```

**Analyze changes**:
- ✅ Gas decreases: Good news! Document savings
- ⚠️ Gas increases: Acceptable if < 5%
- 🔴 Gas increases > 10%: Investigate carefully

---

### Step 5: Extended Security Testing

```bash
# Run Slither analysis
slither . --config-file slither.config.json

# Run Echidna fuzzing (extended campaign)
echidna test/invariants/PaymentOperatorInvariants.sol \
  --contract PaymentOperatorInvariants \
  --config echidna.yaml
```

**Expected**:
- Slither: Same findings as before (or fewer)
- Echidna: All 10 invariants passing after 100k sequences

**If new issues**:
- May indicate compiler bug (rare)
- May expose existing issue (good to catch!)
- Review and address before deploying

---

### Step 6: Update Documentation

If gas costs changed significantly:

1. Update `README.md` gas benchmarks
2. Update `GAS_OPTIMIZATION_REPORT.md`
3. Document compiler version change in changelog

```bash
# Generate new gas report
forge snapshot > .gas-snapshot

# Calculate changes
echo "Gas changes after Solidity upgrade to 0.8.X:"
forge snapshot --diff .gas-snapshot-old .gas-snapshot
```

---

### Step 7: Create Pull Request

```bash
# Create branch
git checkout -b upgrade/solidity-0.8.X

# Commit changes
git add foundry.toml .gas-snapshot README.md
git commit -m "build: upgrade Solidity to 0.8.X

- Update compiler version in foundry.toml
- Re-generate gas snapshot
- Update documentation

Gas changes:
- Authorization: -2.3% (11k gas saved)
- Release: -1.8% (10k gas saved)
- Refund: No change

All tests passing. Slither analysis clean. Echidna 100k sequences passed.

Closes #XXX (Solidity update issue)"

# Push
git push origin upgrade/solidity-0.8.X

# Create PR via GitHub CLI
gh pr create --title "Upgrade Solidity to 0.8.X" \
  --body "Upgrades Solidity compiler from 0.8.Y to 0.8.X.

## Changes
- Update \`foundry.toml\`
- Regenerate gas snapshot

## Testing
- ✅ All 32 tests passing
- ✅ Slither analysis clean
- ✅ Echidna 100k sequences passed
- ✅ Gas benchmarks within acceptable range

## Gas Impact
- Overall: -2% average (optimizations from new compiler)
- No functions exceed 5% increase threshold

Closes #XXX"
```

---

## Version Strategy

### Patch Versions (0.8.33 → 0.8.34)

**Frequency**: Every 1-2 months
**Risk**: Low
**Impact**: Bug fixes, minor optimizations

**Action**:
- ✅ Upgrade immediately if bug fixes relevant
- ⏸️ Can wait for next minor release if not urgent

**Example**:
```
0.8.33 → 0.8.34: Fixed optimizer bug in specific edge case
Impact: Low (we don't use affected feature)
Action: Upgrade when convenient (next release cycle)
```

---

### Minor Versions (0.8.33 → 0.9.0)

**Frequency**: Every 6-12 months
**Risk**: Medium
**Impact**: New features, gas optimizations, potential breaking changes

**Action**:
- ⚠️ Review breaking changes carefully
- ✅ Upgrade if gas optimizations significant
- ⏸️ Can wait if no compelling features

**Example**:
```
0.8.28 → 0.8.33: Transient storage support (EIP-1153), gas optimizations
Impact: High (we use transient storage via Solady)
Action: Upgrade to benefit from native support
```

---

### Major Versions (0.8.x → 1.0.0)

**Frequency**: Rare (years)
**Risk**: High
**Impact**: Major language changes, significant breaking changes

**Action**:
- 🔴 Plan carefully, allocate dedicated time
- ✅ Review all breaking changes
- ✅ Test extensively
- ✅ Consider external audit after upgrade

**Example**:
```
0.8.x → 1.0.0: Major language redesign (hypothetical)
Impact: Critical (likely requires significant code changes)
Action: Plan upgrade as separate project phase
```

---

## Common Issues and Solutions

### Issue 1: Compilation Errors After Upgrade

**Symptoms**:
```
Error: ParserError: Expected ';' but got 'identifier'
```

**Causes**:
- Breaking change in syntax
- Deprecated feature removed
- New reserved keyword

**Solution**:
1. Read breaking changes section in release notes
2. Update code syntax as needed
3. Replace deprecated features with alternatives

---

### Issue 2: New Compiler Warnings

**Symptoms**:
```
Warning: Unused function parameter. Remove or comment out the variable name to silence this warning.
```

**Types**:
- Informational: Safe to ignore or fix
- Deprecation: Should fix before feature removed
- Security: Must address immediately

**Solution**:
```bash
# Review all warnings
forge build 2>&1 | grep "Warning"

# Address security warnings immediately
# Fix deprecation warnings when convenient
# Informational warnings can be addressed gradually
```

---

### Issue 3: Gas Cost Increases

**Symptoms**: Gas costs increase after upgrade (rare)

**Possible Causes**:
- Compiler regression (very rare)
- New safety checks
- Optimization trade-offs

**Solution**:
1. Verify increase is real (not test issue)
2. Check if increase is acceptable (< 5%)
3. If > 5%, investigate or revert upgrade
4. Report to Solidity team if suspected regression

```bash
# Detailed comparison
forge snapshot --diff .gas-snapshot-old .gas-snapshot-new > gas-analysis.txt

# Analyze by function
cat gas-analysis.txt | grep "^+"  # Increases
cat gas-analysis.txt | grep "^-"  # Decreases
```

---

### Issue 4: Test Failures

**Symptoms**: Tests pass on old version, fail on new version

**Possible Causes**:
- Subtle behavior change (breaking change)
- Exposed existing bug (good!)
- Test relies on compiler-specific behavior

**Solution**:
1. Identify failing test
2. Compare behavior between versions
3. Update test if compiler behavior improved
4. Update code if test exposed real issue

```bash
# Run specific test with both versions
forge test --match-test testName -vvv

# Compare output between versions
```

---

## Optimization Opportunities

### Via-IR Improvements

Solidity's IR-based optimizer improves with each release.

**Benefits**:
- Better function inlining
- More efficient stack management
- Cross-function optimizations

**Already enabled** in `foundry.toml`:
```toml
via_ir = true
optimizer = true
optimizer_runs = 200
```

**Expected**: 1-5% gas savings per minor release

---

### Transient Storage (EIP-1153)

Native support improves efficiency of temporary storage.

**Currently using**: Solady's `ReentrancyGuardTransient`
**Future**: Native `transient` keyword

**Migration** (when available):
```solidity
// Current (via Solady)
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

// Future (native)
contract PaymentOperator {
    transient uint256 _reentrancyGuard;
}
```

---

### Immutable Gas Optimizations

Newer compilers better optimize immutable variable access.

**Already using** in `PaymentOperator`:
```solidity
IAuthCaptureEscrow public immutable ESCROW;
uint256 public immutable MAX_TOTAL_FEE_RATE;
```

**Benefit**: Compiler inlines values more efficiently

---

## Rollback Procedure

If upgrade causes issues:

### Step 1: Revert Compiler Version

```bash
# Edit foundry.toml
sed -i 's/solc = "0.8.34"/solc = "0.8.33"/' foundry.toml

# Rebuild
forge clean
forge build

# Verify tests pass
forge test
```

---

### Step 2: Restore Gas Baseline

```bash
# Restore old snapshot
cp .gas-snapshot-old .gas-snapshot

# Verify
forge snapshot --check
```

---

### Step 3: Document Rollback

```bash
# Commit rollback
git add foundry.toml .gas-snapshot
git commit -m "revert: rollback Solidity to 0.8.33

Solidity 0.8.34 caused [describe issue].

Issues encountered:
- [Issue 1]
- [Issue 2]

Will investigate further before next upgrade attempt.

See #XXX for details."
```

---

## Checklist

Use this checklist when upgrading:

### Pre-Upgrade

- [ ] Review Solidity release notes
- [ ] Check for breaking changes
- [ ] Backup current gas snapshot
- [ ] Create upgrade branch

### Testing

- [ ] Update `foundry.toml`
- [ ] Run `forge clean && forge build`
- [ ] Run `forge test -vvv` (all tests pass)
- [ ] Run `forge snapshot` (generate new baseline)
- [ ] Compare gas costs (< 5% increase acceptable)
- [ ] Run `slither . --config-file slither.config.json`
- [ ] Run extended Echidna campaign (100k sequences)
- [ ] Review new compiler warnings

### Documentation

- [ ] Update `README.md` gas benchmarks (if changed)
- [ ] Update `GAS_OPTIMIZATION_REPORT.md` (if needed)
- [ ] Document compiler version in changelog

### Deployment

- [ ] Create pull request
- [ ] Request review
- [ ] Merge after approval
- [ ] Tag release
- [ ] Close Solidity update issue

---

## Monitoring Dashboard

Track Solidity releases:

**Official Sources**:
- [GitHub Releases](https://github.com/ethereum/solidity/releases)
- [Solidity Blog](https://blog.soliditylang.org/)
- [Twitter @solidity_lang](https://twitter.com/solidity_lang)

**Automated**:
- GitHub Issues (created by workflow)
- Weekly monitoring workflow
- Slack/Discord notifications (if configured)

---

## FAQ

**Q: How often should we upgrade?**
A: Minor versions (0.8.X): Every 2-3 releases or when gas optimizations significant. Patch versions: As needed for bug fixes.

**Q: What if tests fail after upgrade?**
A: Review breaking changes, update code if needed, or revert upgrade and investigate.

**Q: Should we upgrade for gas savings?**
A: If savings > 3% across multiple functions, upgrade is worthwhile. For < 1%, wait for more significant release.

**Q: What about audited code?**
A: Compiler upgrades don't require re-audit unless code changes to accommodate breaking changes.

**Q: How to handle virtual modifier deprecation?**
A: Not urgent. Solidity team will provide migration guide. Update when non-virtual syntax available.

---

## Version History

| Date | Compiler Version | Gas Impact | Notes |
|------|-----------------|------------|-------|
| 2026-01-25 | 0.8.33 | Baseline | Current version with via-IR |

---

**Last Updated**: 2026-01-25
**Next Review**: Weekly (automated)
