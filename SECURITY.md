# Security Policy

## Reporting a Vulnerability

**DO NOT** create a public GitHub issue for security vulnerabilities.

### Private Disclosure

Please report security vulnerabilities via one of these methods:

1. **Email**: security@x402r.com (preferred)
2. **GitHub Security Advisories**: [Report a vulnerability](https://github.com/x402r/x402r-contracts/security/advisories/new)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Suggested fix (if any)

### Response Timeline

| Action | Timeline |
|--------|----------|
| Initial acknowledgment | 24 hours |
| Severity assessment | 48 hours |
| Fix development | 1-7 days (severity dependent) |
| Public disclosure | After fix deployed + 7 days |

---

## Incident Response Plan

### Severity Levels

| Level | Description | Examples | Response Time |
|-------|-------------|----------|---------------|
| **CRITICAL** | Active exploit, funds at risk | Reentrancy drain, access control bypass | Immediate (< 1 hour) |
| **HIGH** | Exploitable vulnerability, no active exploit | Logic error enabling theft | < 24 hours |
| **MEDIUM** | Limited impact vulnerability | DoS, griefing attacks | < 72 hours |
| **LOW** | Minor issues, best practice violations | Gas inefficiency, code quality | Next release |

### Emergency Contacts

| Role | Responsibility |
|------|---------------|
| **Security Lead** | Triage, coordinate response |
| **Contract Owner** | Execute emergency transactions |
| **Multisig Signers** | Approve emergency actions |

### Response Procedures

#### Phase 1: Detection & Triage (0-1 hour)

```
1. [ ] Confirm the vulnerability/incident
2. [ ] Assess severity level
3. [ ] Alert security lead and contract owner
4. [ ] Begin incident log documentation
5. [ ] Determine if emergency action needed
```

#### Phase 2: Containment (1-4 hours)

**For CRITICAL/HIGH severity:**

```
1. [ ] Disable fees if attack vector involves fee distribution
       - Owner calls: queueFeesEnabled(false) + executeFeesEnabled()
       - Note: 24h timelock may delay this - consider pre-queued emergency disable

2. [ ] Alert users via official channels:
       - Twitter/X
       - Discord
       - Telegram

3. [ ] Contact affected protocols/integrators

4. [ ] If funds at risk, coordinate with:
       - Block builders (Flashbots) for tx censoring
       - Exchanges for deposit monitoring
       - Bridge operators if cross-chain
```

#### Phase 3: Investigation (4-24 hours)

```
1. [ ] Root cause analysis
2. [ ] Determine scope of impact
3. [ ] Identify affected addresses/transactions
4. [ ] Develop fix or mitigation
5. [ ] Internal security review of fix
```

#### Phase 4: Remediation (24-72 hours)

```
1. [ ] Deploy fix (if contract upgrade possible)
2. [ ] For immutable contracts:
       - Deploy new version
       - Coordinate migration
       - Update integrators

3. [ ] Verify fix effectiveness
4. [ ] Monitor for continued exploitation
```

#### Phase 5: Recovery & Disclosure (72+ hours)

```
1. [ ] Assess total impact (funds lost, users affected)
2. [ ] Determine recovery options:
       - Protocol treasury compensation
       - Insurance claims
       - Negotiation with attacker (if applicable)

3. [ ] Prepare post-mortem report
4. [ ] Public disclosure (after fix + 7 days)
5. [ ] Update security documentation
```

---

## Emergency Actions

### Contract-Level Controls

| Action | Method | Timelock |
|--------|--------|----------|
| Disable fees | `queueFeesEnabled(false)` → `executeFeesEnabled()` | 24 hours |
| Rescue stuck ETH | `rescueETH()` | None (owner only) |
| Transfer ownership | `requestOwnershipHandover()` → `completeOwnershipHandover()` | 48 hours |

### Limitations (Immutable Contracts)

These contracts are **immutable** - no pause function, no upgrades:

- `ArbitrationOperator` - Cannot pause payments
- `EscrowPeriodCondition` - Cannot modify escrow period
- `PayerFreezePolicy` - Cannot change freeze rules

**Mitigation for immutable contracts:**
1. Deploy new version with fix
2. Coordinate with integrators to migrate
3. Old contracts remain functional but should not be used

### Pre-positioned Emergency Actions

To reduce response time for CRITICAL incidents, consider:

```solidity
// Pre-queue a fee disable that can be executed immediately if needed
// Run this periodically to maintain a "ready" state
operator.queueFeesEnabled(false);

// If emergency occurs, execute immediately (if 24h has passed)
operator.executeFeesEnabled();

// Then re-queue for next potential emergency
operator.queueFeesEnabled(true);
// ... wait 24h ...
operator.executeFeesEnabled();
operator.queueFeesEnabled(false); // Ready for next emergency
```

---

## Monitoring & Detection

Monitor these events for anomalies:

| Event | Contract | Alert Condition |
|-------|----------|-----------------|
| `AuthorizationCreated` | ArbitrationOperator | Unusual volume, large amounts |
| `ReleaseExecuted` | ArbitrationOperator | Rapid releases, unusual patterns |
| `RefundExecuted` | ArbitrationOperator | High refund rate |
| `PaymentFrozen` | EscrowPeriodRecorder | Mass freezing |
| `FeesDistributed` | ArbitrationOperator | Unexpected distribution |

For monitoring setup guides (OpenZeppelin Defender, Tenderly, Forta), see [docs.x402r.org/monitoring](https://docs.x402r.org/monitoring).

---

## Bug Bounty Program

**Coming soon** - A bug bounty program will be launched after the contracts have been audited.

---

## Post-Incident Checklist

After any security incident:

- [ ] Incident log completed with timeline
- [ ] Root cause identified
- [ ] Fix deployed and verified
- [ ] Affected users notified
- [ ] Post-mortem written
- [ ] Security documentation updated
- [ ] Monitoring rules updated
- [ ] Team retrospective conducted
- [ ] Public disclosure published (if applicable)

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-01-25 | 1.0.0 | Initial security policy |

---

## Contact

- **Security Email**: security@x402r.com
- **General Inquiries**: team@x402r.com
- **Twitter**: [@x402r](https://twitter.com/x402r)
