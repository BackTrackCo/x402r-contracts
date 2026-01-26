# Dependency Monitoring and Maintenance

## Purpose

This document outlines the process for monitoring and updating external dependencies, particularly security-critical libraries like Solady, OpenZeppelin, and Forge-std.

---

## Critical Dependencies

### 1. Solady (solady-js/solady)

**Usage in Project**:
- `ReentrancyGuardTransient` - Reentrancy protection on PaymentOperator
- `Ownable` - Access control for operators and factories
- `LibClone` - CREATE2 cloning for deterministic deployments
- `SafeTransferLib` - Gas-optimized ERC20 transfers

**Risk Level**: **CRITICAL**
- Uses assembly for gas optimization
- Virtual modifiers (deprecated in Solidity 0.8.33)
- Core security primitive (reentrancy protection)

**Current Version**: Tracked in `lib/solady`

**Update Process**: See section below

---

### 2. OpenZeppelin Contracts

**Usage in Project**:
- `SafeERC20` - Safe token transfer wrappers (via commerce-payments library)
- `IERC20` - ERC20 interface

**Risk Level**: **HIGH**
- Industry-standard library
- Less gas-optimized than Solady
- Well-audited and battle-tested

**Current Version**: Tracked in `lib/openzeppelin-contracts`

**Update Process**: See section below

---

### 3. Forge-std (Foundry Standard Library)

**Usage in Project**:
- Testing utilities only
- Not deployed to mainnet

**Risk Level**: **LOW**
- Development/testing only
- No production security impact

**Current Version**: Tracked in `lib/forge-std`

**Update Process**: Update with Foundry toolchain

---

### 4. Commerce-Payments Library

**Usage in Project**:
- `AuthCaptureEscrow` - Core escrow contract
- `PreApprovalPaymentCollector` - Token collection
- `IOperator`, `ICondition`, `IRecorder` - Interfaces

**Risk Level**: **CRITICAL**
- Internal library (same organization)
- Contains escrow logic

**Current Version**: Tracked in `lib/commerce-payments`

**Update Process**: See section below

---

## Monitoring Process

### Daily Monitoring

**GitHub Watch Notifications** (Recommended):

1. Navigate to each repository:
   - https://github.com/Vectorized/solady
   - https://github.com/OpenZeppelin/openzeppelin-contracts
   - https://github.com/foundry-rs/forge-std

2. Click "Watch" → "Custom" → Enable:
   - ✅ Releases
   - ✅ Security advisories
   - ❌ All activity (too noisy)

3. Configure email notifications:
   - GitHub Settings → Notifications → Email
   - Ensure security-related notifications enabled

---

### Weekly Monitoring

**Automated Dependency Scanning** (GitHub Dependabot):

Enable Dependabot in repository:

```yaml
# .github/dependabot.yml
version: 2
updates:
  # Monitor git submodules
  - package-ecosystem: "gitsubmodule"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"

  # Monitor GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

**Manual Version Checks**:

Run weekly (or before major releases):

```bash
# Check current versions
cd lib/solady && git log -1 --oneline && cd ../..
cd lib/openzeppelin-contracts && git log -1 --oneline && cd ../..
cd lib/commerce-payments && git log -1 --oneline && cd ../..

# Check for updates
git submodule update --remote --merge

# Review changes
git diff lib/solady
git diff lib/openzeppelin-contracts
git diff lib/commerce-payments
```

---

### Security Advisory Monitoring

**GitHub Security Advisories**:

1. **Solady**:
   - https://github.com/Vectorized/solady/security/advisories
   - No known vulnerabilities as of 2026-01-25

2. **OpenZeppelin**:
   - https://github.com/OpenZeppelin/openzeppelin-contracts/security/advisories
   - Subscribe to: https://blog.openzeppelin.com/security-audits

3. **Trail of Bits Monitoring**:
   - Subscribe to: https://blog.trailofbits.com
   - Check for Solady-related findings

**Security Mailing Lists**:

Subscribe to:
- security@x402r.com (internal security list)
- Ethereum Security Updates: https://ethereum-magicians.org

---

## Update Process

### Step 1: Identify Update

**Trigger Events**:
- Security advisory published
- Major version release
- Critical bug fix
- Scheduled quarterly review

**Severity Assessment**:

| Severity | Response Time | Examples |
|----------|--------------|----------|
| **CRITICAL** | Immediate (< 24h) | Reentrancy vulnerability, funds at risk |
| **HIGH** | 1-3 days | Logic error, DoS vulnerability |
| **MEDIUM** | 1-2 weeks | Gas optimization, non-critical bug |
| **LOW** | Next release | Code cleanup, deprecations |

---

### Step 2: Review Changes

**For Solady Updates**:

```bash
# Fetch latest version
cd lib/solady
git fetch origin
git log HEAD..origin/main --oneline

# Review diff
git diff HEAD..origin/main src/utils/ReentrancyGuardTransient.sol
git diff HEAD..origin/main src/auth/Ownable.sol

# Check for breaking changes
git log HEAD..origin/main --grep="BREAKING"
```

**Review Checklist**:
- [ ] Read release notes
- [ ] Check for API changes
- [ ] Review security implications
- [ ] Identify affected contracts
- [ ] Check for Solidity version requirements

---

### Step 3: Test Update

**Testing Process**:

```bash
# Create feature branch
git checkout -b dep/update-solady-$(date +%Y%m%d)

# Update submodule
cd lib/solady
git checkout main
git pull
cd ../..
git add lib/solady

# Run full test suite
forge clean
forge test -vvv

# Run specific security tests
forge test --match-contract ReentrancyAttackTest -vvv
forge test --match-contract PaymentOperatorInvariants -vvv

# Run extended fuzzing campaign
echidna test/invariants/PaymentOperatorInvariants.sol \
  --contract PaymentOperatorInvariants \
  --config echidna.yaml
```

**Compilation Checks**:

```bash
# Check for compilation errors
forge build

# Check for new warnings
forge build 2>&1 | grep -i "warning"

# Verify gas changes
forge snapshot --diff
```

---

### Step 4: Security Review

**Static Analysis**:

```bash
# Run Slither with updated dependencies
slither . --config-file slither.config.json

# Compare with previous results
diff slither-report-old.json slither-report-new.json

# Check for new detectors triggered
slither . --list-detectors
```

**Manual Review**:

For critical dependencies (Solady):
1. Review assembly changes
2. Verify reentrancy guard logic unchanged
3. Check for new modifiers or storage patterns
4. Validate gas optimizations don't break security

---

### Step 5: Deploy and Monitor

**Deployment Process**:

```bash
# Merge update
git commit -m "deps: update Solady to v0.x.x"
git push origin dep/update-solady-$(date +%Y%m%d)

# Create PR with:
# - Release notes summary
# - Test results
# - Slither comparison
# - Gas snapshot diff
# - Security review summary

# After merge, tag release
git tag -a v1.x.x -m "Update Solady to v0.x.x"
git push origin v1.x.x
```

**Post-Deployment Monitoring**:

Monitor for 7 days after update:
- [ ] No new Slither findings
- [ ] No unexpected reverts
- [ ] Gas usage within expected range
- [ ] Fuzzing campaigns passing
- [ ] No user reports of issues

---

## Vulnerability Response

### If Security Advisory Published

**Immediate Actions** (< 1 hour):

```
1. [ ] Assess impact on x402r-contracts
2. [ ] Check if vulnerability affects used functions
3. [ ] Determine severity level
4. [ ] Alert security team
5. [ ] Begin hotfix process if critical
```

**Example: Reentrancy Guard Vulnerability**

If Solady ReentrancyGuardTransient has vulnerability:

```bash
# Step 1: Verify impact
cd lib/solady
git log --all --grep="reentrancy" --since="2026-01-01"

# Step 2: Check usage
grep -r "ReentrancyGuardTransient" src/

# Step 3: Apply patch
cd lib/solady
git cherry-pick <security-patch-commit>
cd ../..

# Step 4: Emergency testing
forge test --match-contract ReentrancyAttackTest -vvv

# Step 5: Deploy hotfix
# Follow emergency deployment procedure
```

---

## Deprecation Handling

### Virtual Modifier Deprecation (Solidity 0.8.33)

**Current Warnings**:

```
Warning (8429): Virtual modifiers are deprecated and scheduled for removal.
  --> lib/solady/src/utils/ReentrancyGuardTransient.sol:31:5:
   |
31 |     modifier nonReentrant() virtual {
   |     ^ (Relevant source part starts here and spans across multiple lines).
```

**Status**: Non-critical warning
- Solidity team will provide migration path
- Solady maintainers will update before removal
- No immediate action required

**Monitoring**:
- Watch Solidity release notes for deprecation timeline
- Track Solady issues: https://github.com/Vectorized/solady/issues
- Update when non-virtual version available

---

## Quarterly Dependency Review

**Schedule**: First week of each quarter (Jan, Apr, Jul, Oct)

**Process**:

```bash
# 1. Generate dependency report
forge tree > dependency-tree.txt
cat dependency-tree.txt

# 2. Check for unused dependencies
# Review each library in lib/

# 3. Version audit
cd lib/solady && git describe --tags && cd ../..
cd lib/openzeppelin-contracts && git describe --tags && cd ../..

# 4. Security audit status
# Check when each library was last audited
# Review audit reports for changes since last update

# 5. Update roadmap
# Plan updates for next quarter
# Schedule testing sprints
```

**Quarterly Report Template**:

```markdown
# Dependency Review - Q1 2026

## Summary
- Solady: v0.x.x (last updated: 2026-01-15)
- OpenZeppelin: v5.x.x (last updated: 2025-12-01)
- Commerce-Payments: latest (internal)

## Security Status
- [ ] No known vulnerabilities
- [ ] All dependencies < 3 months old
- [ ] All audit findings addressed

## Planned Updates
- Q2 2026: Update Solady to v0.x.x+1 (new gas optimizations)
- Q3 2026: Major OpenZeppelin upgrade (if needed)

## Risks
- Low: Virtual modifier deprecation (Solady)
- None: OpenZeppelin stable
```

---

## Contact Information

**Security Issues**:
- Email: security@x402r.com
- GitHub: [Create Security Advisory](https://github.com/x402r/x402r-contracts/security/advisories/new)

**Dependency Maintainers**:
- Solady: @Vectorized (GitHub)
- OpenZeppelin: security@openzeppelin.com
- Commerce-Payments: Internal team

**Emergency Contacts**:
- Security Lead: TBD
- Contract Owner: TBD
- DevOps: TBD

---

## Tools and Automation

### Recommended Tools

**1. Dependency Tracking**:
- GitHub Dependabot (automated PRs)
- Renovate Bot (more configurable)
- Socket.dev (supply chain security)

**2. Security Scanning**:
- Slither (static analysis)
- Echidna (property testing)
- MythX (optional: cloud-based analysis)

**3. Monitoring Services**:
- GitHub Security Advisories (free)
- OpenSSF Scorecard (supply chain metrics)
- Socket.dev Alerts (dependency monitoring)

---

### Automation Scripts

**Daily Dependency Check** (`scripts/check-deps.sh`):

```bash
#!/bin/bash
# Check for dependency updates

echo "Checking Solady..."
cd lib/solady
SOLADY_LATEST=$(git ls-remote origin main | cut -f1)
SOLADY_CURRENT=$(git rev-parse HEAD)
if [ "$SOLADY_LATEST" != "$SOLADY_CURRENT" ]; then
    echo "⚠️ Solady update available"
fi
cd ../..

echo "Checking OpenZeppelin..."
cd lib/openzeppelin-contracts
OZ_LATEST=$(git ls-remote origin master | cut -f1)
OZ_CURRENT=$(git rev-parse HEAD)
if [ "$OZ_LATEST" != "$OZ_CURRENT" ]; then
    echo "⚠️ OpenZeppelin update available"
fi
cd ../..

echo "Dependency check complete"
```

**Run daily in CI**:

```yaml
# .github/workflows/dependency-check.yml
name: Dependency Check

on:
  schedule:
    - cron: '0 9 * * *'  # Daily at 9 AM UTC

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive
      - name: Check dependencies
        run: bash scripts/check-deps.sh
```

---

## Version History

| Date | Change | Reason |
|------|--------|--------|
| 2026-01-25 | Initial version | Document monitoring process |

---

**Last Updated**: 2026-01-25
**Next Review**: 2026-04-01 (Quarterly Review)
