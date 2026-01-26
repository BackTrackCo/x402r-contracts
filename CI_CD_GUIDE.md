# CI/CD Guide

## Overview

This project includes comprehensive CI/CD workflows for continuous security monitoring, fuzzing, and gas optimization tracking.

---

## Workflows

### 1. Echidna Fuzzing Campaign (`fuzzing.yml`)

**Purpose**: Continuous property-based fuzzing to detect invariant violations

**Triggers**:
- Push to `main` or `develop` (10,000 sequences)
- Pull requests (1,000 sequences quick check)
- Daily at 2 AM UTC (100,000 sequences extended campaign)
- Manual dispatch with custom parameters

**Jobs**:

#### Quick Fuzzing (PRs)
- **Timeout**: 15 minutes
- **Test Limit**: 1,000 sequences
- **Sequence Length**: 50
- **Purpose**: Fast feedback on PRs

#### Standard Fuzzing (Main/Develop)
- **Timeout**: 30 minutes
- **Test Limit**: 10,000 sequences
- **Sequence Length**: 100
- **Purpose**: Standard validation on merges

#### Extended Fuzzing (Nightly)
- **Timeout**: 120 minutes
- **Test Limit**: 100,000 sequences (from echidna.yaml)
- **Sequence Length**: 150
- **Purpose**: Deep security validation
- **Artifacts**: Results retained for 30 days

**Invariants Tested**:
- ✅ echidna_no_double_spend (P4)
- ✅ echidna_solvency
- ✅ echidna_balance_validation_enforced (P20)
- ✅ echidna_captured_monotonic
- ✅ echidna_fee_not_excessive (P16)
- ✅ echidna_reentrancy_protected (P22)
- ✅ echidna_owner_cannot_steal_escrow
- ✅ echidna_fee_recipient_balance_increases
- ✅ echidna_refunded_monotonic
- ✅ echidna_payment_hash_unique

**Failure Handling**:
- Creates GitHub issue on extended campaign failures
- Posts results to PR comments
- Uploads corpus and results as artifacts

---

### 2. Gas Report (`gas-report.yml`)

**Purpose**: Track gas consumption and detect regressions

**Triggers**:
- Push to `main` or `develop`
- Pull requests (with diff comparison)

**Jobs**:

#### Gas Report (PRs)
- Generates current gas snapshot
- Compares with base branch
- Posts diff to PR comments
- Warns on > 5% increases

**Example PR Comment**:
```markdown
## ⛽ Gas Report

### Significant Increases (> 5%)
- ⚠️ `authorize_function`: +7% (+34,500 gas)

### Significant Decreases (> 5%)
- ✅ `release_function`: -6% (-28,000 gas)
```

#### Gas Benchmark (Main Branch)
- Updates `.gas-snapshot` baseline
- Calculates statistics (avg, min, max)
- Commits updated snapshot to repo
- Stores benchmarks (90-day retention)

**Artifacts**:
- `.gas-snapshot-new` - Current snapshot
- `.gas-snapshot-base` - Baseline for comparison
- `gas-diff.txt` - Full diff
- `gas-analysis.txt` - Statistical analysis

---

### 3. Security Analysis (`security.yml`)

**Purpose**: Continuous security monitoring with Slither and dependency checks

**Triggers**:
- Push to `main` or `develop`
- Pull requests
- Weekly on Sundays at 3 AM UTC
- Manual dispatch

**Jobs**:

#### Slither Static Analysis
- Runs Slither with project configuration
- Uploads SARIF to GitHub Security tab
- Posts summary to PR comments
- **Fails CI if high severity issues found**

**Example Output**:
```markdown
## 🔍 Slither Security Analysis

- 🔴 High: 0
- 🟠 Medium: 5 (all triaged)
- 🟡 Low: 10 (benign)
- ℹ️ Informational: 0
```

#### Test Coverage
- Generates LCOV coverage report
- Uploads coverage artifacts
- Tracks coverage trends

#### Dependency Security Check
- Checks Solady age (warns if > 6 months old)
- Checks OpenZeppelin age
- Links to security advisories

#### Comprehensive Security Check (Weekly)
- Human-readable summary
- Contract summary
- Function summary
- Variables and authorization analysis
- Creates GitHub issue if failures detected

**Artifacts**:
- `slither-report.json` - Machine-readable results
- `slither-results.sarif` - GitHub Security format
- `slither-output.txt` - Full output
- `comprehensive-report.txt` - Weekly detailed analysis

---

## GitHub Security Integration

### Security Tab Features

The workflows automatically populate the **Security** tab with:

1. **Code Scanning Alerts** (from Slither SARIF uploads)
   - Navigate to: `Security` → `Code scanning`
   - View findings by severity
   - Track remediation status

2. **Dependabot Alerts** (if enabled)
   - Automated dependency updates
   - Security vulnerability notifications

3. **Secret Scanning** (if enabled)
   - Detects committed secrets
   - Prevents credential leaks

---

## Setting Up for Your Repository

### Prerequisites

1. **GitHub Actions enabled** in repository settings
2. **Permissions** for workflows:
   - `contents: write` (for committing gas snapshots)
   - `issues: write` (for creating security issues)
   - `pull-requests: write` (for commenting)
   - `security-events: write` (for SARIF uploads)

### Configuration Steps

#### 1. Enable Workflows

```bash
# Workflows are in .github/workflows/
ls -la .github/workflows/
# fuzzing.yml
# gas-report.yml
# security.yml
```

**All workflows are enabled by default when pushed to GitHub.**

---

#### 2. Configure GitHub Security Features

Navigate to: `Settings` → `Security & analysis`

Enable:
- ✅ Dependency graph
- ✅ Dependabot alerts
- ✅ Dependabot security updates
- ✅ Code scanning (auto-configured by workflows)
- ✅ Secret scanning (if private repo)

---

#### 3. Set Up Branch Protection

Navigate to: `Settings` → `Branches` → `Branch protection rules`

For `main` branch, enable:
- ✅ Require status checks to pass before merging
  - ✅ `slither-analysis`
  - ✅ `quick-fuzzing` (for PRs)
  - ✅ `gas-report`
- ✅ Require branches to be up to date before merging

---

#### 4. Configure Notifications

Navigate to: `Settings` → `Notifications`

Subscribe to:
- ✅ Actions workflow run failures
- ✅ Security alerts
- ✅ Dependabot alerts

---

## Running Workflows Manually

### Fuzzing Campaign

Trigger custom fuzzing run:

```bash
# Via GitHub UI
1. Go to Actions → Echidna Fuzzing Campaign
2. Click "Run workflow"
3. Select branch
4. Set parameters:
   - test_limit: 50000
   - seq_len: 150
5. Run workflow
```

### Security Scan

Trigger comprehensive security analysis:

```bash
# Via GitHub UI
1. Go to Actions → Security Analysis
2. Click "Run workflow"
3. Select branch
4. Run workflow
```

---

## Monitoring and Alerts

### Email Notifications

Configure in: `Settings` → `Notifications` → `Email preferences`

You'll receive emails for:
- ❌ Workflow failures
- 🔴 High severity security findings
- 🚨 Extended fuzzing campaign failures
- 📊 Weekly security scan results

---

### Slack Integration (Optional)

Add Slack webhook for real-time notifications:

```yaml
# Add to workflow:
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "❌ ${{ github.workflow }} failed",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Workflow:* ${{ github.workflow }}\n*Status:* Failed\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Details>"
            }
          }
        ]
      }
```

---

## Troubleshooting

### Workflow Failures

#### Fuzzing Fails: "Echidna not found"

**Solution**: Echidna installation is automated in workflow. If failing:
1. Check Echidna release availability
2. Update Echidna version in workflow
3. Use Docker image as fallback

#### Slither Fails: "Compilation error"

**Solution**: Ensure Foundry compilation works:
```bash
forge build
# If successful, Slither should work
```

#### Gas Report Fails: "No baseline snapshot"

**Solution**: First run won't have baseline (expected). Subsequent runs will compare.

#### Workflow Timeout

**Solution**: Increase timeout or reduce test parameters:
```yaml
timeout-minutes: 60  # Increase from 30
```

---

### Permission Errors

If workflows fail with "Permission denied":

1. Check repository settings: `Settings` → `Actions` → `General`
2. Ensure "Read and write permissions" enabled
3. For security, use fine-grained tokens

---

### Artifact Storage Limits

**GitHub Free**: 500 MB storage, 2000 minutes/month
**GitHub Pro**: 1 GB storage, 3000 minutes/month

**Optimization**:
- Reduce artifact retention days
- Compress large reports
- Archive old artifacts

---

## Cost Optimization

### GitHub Actions Minutes

**Current Usage Estimate**:
- Quick fuzzing: ~5 min per PR
- Standard fuzzing: ~15 min per push
- Extended fuzzing: ~60 min per night
- Gas report: ~3 min per PR
- Security scan: ~5 min per PR
- **Total: ~500 min/month** (well within free tier)

**Optimization Tips**:
1. Cache dependencies (Foundry, Slither)
2. Run extensive checks only on schedules
3. Use matrix builds for parallelization
4. Fail fast on early errors

---

### Artifact Storage

**Current Usage Estimate**:
- Fuzzing corpus: ~10 MB per run
- Gas snapshots: ~10 KB per run
- Slither reports: ~100 KB per run
- **Total: ~500 MB/month** (within free tier)

**Optimization Tips**:
1. Reduce retention days (30 → 7 for non-critical)
2. Compress large artifacts
3. Store only extended campaign results long-term

---

## Maintenance

### Weekly Tasks

- [ ] Review security scan results
- [ ] Check for new security advisories
- [ ] Review gas trends (increases/decreases)
- [ ] Investigate fuzzing corpus changes

### Monthly Tasks

- [ ] Update dependencies if advisories published
- [ ] Review workflow execution times
- [ ] Optimize slow jobs
- [ ] Archive old artifacts

### Quarterly Tasks

- [ ] Update Echidna version
- [ ] Update Slither version
- [ ] Review and update security configurations
- [ ] Audit CI/CD costs and optimize

---

## Advanced Configuration

### Parallel Fuzzing

Run multiple fuzzing campaigns in parallel:

```yaml
strategy:
  matrix:
    contract: [PaymentOperator, RefundRequest, EscrowPeriod]
steps:
  - name: Fuzz ${{ matrix.contract }}
    run: echidna test/invariants/${{ matrix.contract }}Invariants.sol
```

### Custom Slither Detectors

Add project-specific detectors:

```python
# slither_detectors/custom_detector.py
from slither.detectors.abstract_detector import AbstractDetector

class CustomDetector(AbstractDetector):
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.HIGH

    def _detect(self):
        # Custom logic here
        pass
```

### Integration with Other Tools

#### MythX (Optional)

```yaml
- name: Run MythX
  uses: mythx/mythx-cli-action@v1
  with:
    mythx-api-key: ${{ secrets.MYTHX_API_KEY }}
```

#### Certora (Optional)

```yaml
- name: Run Certora
  run: |
    certoraRun src/PaymentOperator.sol \
      --verify PaymentOperator:spec/PaymentOperator.spec
```

---

## Best Practices

### 1. Fast Feedback Loop ⭐

- Quick checks on PRs (< 5 min)
- Extended checks on merges
- Deep analysis on schedules

### 2. Fail Fast ⭐

- Exit early on critical errors
- Don't run gas reports if tests fail
- Block merges on high severity issues

### 3. Informative Failures ⭐

- Clear error messages
- Link to relevant logs
- Suggest fixes when possible

### 4. Progressive Enhancement ⭐

- Start with basic checks
- Add more sophisticated analysis over time
- Monitor execution times

### 5. Security First ⭐

- Never skip security checks
- Treat warnings as errors for security
- Automate security updates

---

## FAQ

**Q: Why are fuzzing campaigns so long?**
A: Property-based fuzzing needs many sequences to explore state space. 100k sequences provide high confidence.

**Q: Can I skip security checks for hotfixes?**
A: No. Use `workflow_dispatch` for emergency deploys, but always run security checks after.

**Q: How do I add new invariants?**
A: Add `echidna_*` function to PaymentOperatorInvariants.sol. Workflow auto-detects it.

**Q: Why does gas increase sometimes?**
A: Security features (reentrancy guards), new functionality, or compiler changes can increase gas.

**Q: Should I commit .gas-snapshot?**
A: Yes. It's your baseline for detecting regressions.

---

## Support

**Issues with Workflows**:
- Check [GitHub Actions Status](https://www.githubstatus.com/)
- Review workflow logs in Actions tab
- Open issue in repository

**Security Concerns**:
- Email: security@x402r.com
- GitHub Security Advisories (private disclosure)

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-25 | 1.0.0 | Initial CI/CD setup |

---

**Last Updated**: 2026-01-25
