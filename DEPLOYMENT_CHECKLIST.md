# Deployment Checklist

Use this checklist for every mainnet deployment to ensure nothing is missed.

---

## Pre-Deployment Checklist

### Owner Address Verification
- [ ] Owner address is a Gnosis Safe (or equivalent multisig contract)
- [ ] Verified on Basescan: https://basescan.org/address/[OWNER_ADDRESS]
- [ ] Multisig has ≥3 signers with ≥2 threshold (recommended: 3/5 or 5/7)
- [ ] All signer identities verified and documented
- [ ] Signers are geographically distributed
- [ ] At least one signer available 24/7 for emergencies
- [ ] Emergency contact information documented in INCIDENT_RESPONSE.md

### Environment Setup
- [ ] `.env.production` file created from `.env.production.example`
- [ ] All required variables filled in (no placeholders)
- [ ] RPC endpoint tested and working (run `cast block latest --rpc-url $RPC_URL`)
- [ ] Deployer account has sufficient ETH for gas (~0.01 ETH minimum)
- [ ] Etherscan API key configured and valid
- [ ] All dependency contracts deployed and verified on target network

### Configuration Review
- [ ] **Escrow address** correct and verified
- [ ] **Protocol fee recipient** correct (Base protocol address)
- [ ] **Max total fee rate** reasonable (50 bps = 0.5% recommended)
- [ ] **Protocol fee percentage** correct (25% recommended)
- [ ] **Operator fee recipient** correct (your address)
- [ ] **Condition addresses** correct (or address(0) for defaults)
- [ ] **Recorder addresses** correct (or address(0) for defaults)

### Testing & Security
- [ ] **All tests passing** (`forge test`)
  - [ ] 32/32 tests passing
  - [ ] No compilation warnings
- [ ] **Gas benchmarks acceptable** (`forge snapshot`)
  - [ ] No significant regressions
  - [ ] All operations < 1M gas
- [ ] **Echidna fuzzing passed** (100k sequences)
  - [ ] All 10 invariants passing
  - [ ] No property violations
- [ ] **Slither analysis clean** (`slither . --config-file slither.config.json`)
  - [ ] 0 high severity issues
  - [ ] All medium issues triaged
- [ ] **Coverage acceptable** (`forge coverage`)
  - [ ] Critical paths covered
  - [ ] Edge cases tested

### Testnet Validation
- [ ] **Testnet deployment successful** (Base Sepolia)
  - [ ] Deployed using `make deploy-testnet`
  - [ ] Contract verified on Sepolia Basescan
- [ ] **Basic operations tested** on testnet
  - [ ] View functions work
  - [ ] Owner functions work
  - [ ] Payment flow works end-to-end
- [ ] **Integration tests passed** (if applicable)
- [ ] **No issues discovered** during testnet testing

---

## Deployment

### Pre-Flight Checks
- [ ] Read through this entire checklist
- [ ] Team notified of deployment
- [ ] Emergency contacts available
- [ ] Block explorer API responsive
- [ ] Gas prices acceptable (not during network congestion)

### Deployment Execution
```bash
# 1. Source production environment
source .env.production

# 2. Verify owner is multisig
make verify-owner OWNER_ADDRESS=$OWNER_ADDRESS RPC_URL=$RPC_URL

# 3. Deploy to mainnet
make deploy-mainnet
```

- [ ] Ran `make verify-owner` successfully
- [ ] Confirmed owner is multisig (not EOA)
- [ ] Deployment script executed (`make deploy-mainnet`)
- [ ] Manual confirmation provided when prompted
- [ ] Deployment script validated owner is contract
- [ ] Factory contract deployed successfully
- [ ] PaymentOperator contract deployed successfully
- [ ] Transaction confirmed on-chain
- [ ] No errors or warnings during deployment

### Contract Verification
- [ ] Factory verified on Basescan automatically
- [ ] PaymentOperator verified on Basescan automatically
- [ ] If auto-verification failed, manually verify:
  ```bash
  forge verify-contract <ADDRESS> <CONTRACT> --chain base
  ```
- [ ] Source code readable on Basescan
- [ ] Constructor arguments visible

---

## Post-Deployment Verification

### Automated Verification
```bash
# Run post-deployment verification script
OPERATOR_ADDRESS=<deployed_address> \
RPC_URL=$RPC_URL \
node scripts/verify-deployment.js
```

- [ ] Verification script ran successfully
- [ ] Owner address matches expected multisig
- [ ] Owner is contract (not EOA) ✅
- [ ] All immutables set correctly:
  - [ ] ESCROW address correct
  - [ ] FEE_RECIPIENT address correct
  - [ ] MAX_TOTAL_FEE_RATE correct
  - [ ] PROTOCOL_FEE_PERCENTAGE correct
- [ ] Condition/recorder slots match configuration
- [ ] Escrow contract exists at specified address

### Manual Verification
- [ ] Check Factory on Basescan
  - [ ] Contract verified
  - [ ] Owner matches multisig
  - [ ] Read functions work
- [ ] Check PaymentOperator on Basescan
  - [ ] Contract verified
  - [ ] All immutables visible and correct
  - [ ] Read functions work
- [ ] Check Multisig on Basescan
  - [ ] Threshold correct (e.g., 3/5)
  - [ ] All signers identified
  - [ ] Recent activity visible

### Ownership Transfer (if 2-step)
- [ ] Factory ownership pending transfer
- [ ] Multisig signers notified to complete transfer
- [ ] Signers called `completeOwnershipHandover()` from multisig
- [ ] Ownership transfer confirmed on-chain
- [ ] Factory owner now matches multisig address

### Test Basic Operations
- [ ] Call view functions from Basescan
  - [ ] `owner()` returns multisig address
  - [ ] `ESCROW()` returns escrow address
  - [ ] `MAX_TOTAL_FEE_RATE()` returns correct value
- [ ] Verify events are emitted
  - [ ] `OperatorDeployed` event visible
- [ ] Check token store created
  - [ ] Escrow has token store for operator

---

## Documentation

### Update Repository
- [ ] Create deployment record in `deployments/` directory:
  ```
  deployments/
    base-mainnet-2026-01-25.json
  ```
- [ ] Record includes:
  - [ ] Network name and chain ID
  - [ ] Deployment timestamp
  - [ ] Factory address
  - [ ] Operator address
  - [ ] Escrow address
  - [ ] Owner (multisig) address
  - [ ] Transaction hashes
  - [ ] Deployer address
  - [ ] Gas used
  - [ ] Configuration (fees, conditions, recorders)

### Update Documentation Files
- [ ] Update `README.md` with deployed addresses:
  ```markdown
  ## Deployed Contracts

  ### Base Mainnet
  - **PaymentOperator**: `0x...`
  - **PaymentOperatorFactory**: `0x...`
  - **Escrow**: `0x...` (Base Commerce Payments)
  ```
- [ ] Update `docs/DEPLOYMENTS.md` (if exists)
- [ ] Add deployment date to version history
- [ ] Update changelog with deployment announcement

### Git Management
- [ ] Commit deployment artifacts:
  ```bash
  git add deployments/ broadcast/ README.md
  git commit -m "deploy: mainnet deployment on Base (2026-01-25)"
  ```
- [ ] Tag release:
  ```bash
  git tag -a v1.0.0-mainnet -m "Mainnet deployment on Base"
  git push origin v1.0.0-mainnet
  ```
- [ ] Create GitHub release with:
  - [ ] Deployed contract addresses
  - [ ] Link to Basescan
  - [ ] Configuration summary
  - [ ] Security audit report (if applicable)

---

## Communication

### Internal
- [ ] Notify team of successful deployment in team chat
- [ ] Share deployment summary:
  - Contract addresses
  - Basescan links
  - Configuration details
  - Next steps

### Community/Public
- [ ] Announce deployment on Discord/Twitter
- [ ] Post includes:
  - [ ] Network (Base Mainnet)
  - [ ] Contract addresses (with Basescan links)
  - [ ] Brief description of functionality
  - [ ] Link to documentation
  - [ ] Security information (audit status, testing)
- [ ] Update website/app with contract addresses
- [ ] Publish deployment blog post (if applicable)

### Integration Partners
- [ ] Notify integration partners of deployment
- [ ] Provide:
  - [ ] Contract addresses
  - [ ] ABI files
  - [ ] Integration guide
  - [ ] Support contact

---

## Monitoring Setup

### Add to Monitoring Infrastructure
- [ ] Add operator contract to monitoring dashboard
  - [ ] Dune Analytics (if using)
  - [ ] Grafana (if using)
  - [ ] Custom monitoring scripts
- [ ] Configure event monitoring
  - [ ] AuthorizationCreated
  - [ ] ReleaseExecuted
  - [ ] RefundExecuted
  - [ ] FeesDistributed

### Set Up Alerts
- [ ] **Tenderly** alerts configured:
  - [ ] Large refunds (> $10k)
  - [ ] Owner actions (fee changes)
  - [ ] Transaction failures (> 5% rate)
- [ ] **OpenZeppelin Defender** (if using):
  - [ ] Admin actions monitored
  - [ ] Unusual activity alerts
  - [ ] Gas price alerts
- [ ] **Custom alerts** (if applicable):
  - [ ] Slack/Discord webhooks
  - [ ] PagerDuty integration
  - [ ] Email notifications

### Test Alerts
- [ ] Trigger test alert to verify notifications work
- [ ] Confirm all team members receive alerts
- [ ] Verify alert escalation path works

---

## Security

### Deployer Key Management
- [ ] Transfer deployer private key to cold storage
- [ ] Remove private key from deployment machine
- [ ] Document key storage location (secure location only)
- [ ] Ensure key backup exists in multiple secure locations

### Multisig Access
- [ ] Confirm all multisig signers have access
- [ ] Test multisig transaction execution:
  ```bash
  # Execute a view call from multisig
  cast call <OPERATOR> "MAX_TOTAL_FEE_RATE()" --rpc-url $RPC_URL
  ```
- [ ] Verify signers can propose transactions
- [ ] Verify threshold signers can execute
- [ ] Document signing process in team wiki

### Emergency Procedures
- [ ] Review `INCIDENT_RESPONSE.md`
- [ ] Ensure emergency contacts up to date
- [ ] Verify on-call rotation active
- [ ] Test emergency communication channels
- [ ] Confirm access to pause/emergency functions (if applicable)

---

## Post-Deployment Tasks (First 24 Hours)

### Monitoring
- [ ] **Hour 1**: Watch for deployment-related issues
- [ ] **Hour 6**: Check for any unusual activity
- [ ] **Hour 24**: Review first day metrics
  - [ ] Transaction count
  - [ ] Success rate
  - [ ] Gas usage
  - [ ] Error frequency

### Validation
- [ ] Monitor first few real transactions
- [ ] Verify events are emitted correctly
- [ ] Check fee distribution works as expected
- [ ] Ensure escrow interactions function properly

### Team Availability
- [ ] On-call engineer available for first 24 hours
- [ ] Multisig signers on standby
- [ ] Emergency escalation path clear

---

## Post-Deployment Tasks (First Week)

### Metrics Review
- [ ] Daily active users (if applicable)
- [ ] Total value processed
- [ ] Transaction success rate (target: >99%)
- [ ] Average gas costs per operation
- [ ] Refund rate (monitor for abuse)

### Security Monitoring
- [ ] Review all owner actions (should be none immediately)
- [ ] Check for unusual patterns
- [ ] Monitor for potential exploits
- [ ] Review failed transactions for attack attempts

### Documentation
- [ ] Update integration guides based on real usage
- [ ] Document any issues encountered
- [ ] Add FAQ items based on user questions
- [ ] Update gas estimates with real data

---

## Checklist Complete

- [ ] **All items above checked**
- [ ] **Deployment successful**
- [ ] **Contracts verified**
- [ ] **Monitoring active**
- [ ] **Team notified**
- [ ] **Community informed**

---

## Deployment Record

**Date**: ________________
**Network**: Base Mainnet (Chain ID: 8453)
**Deployed By**: ________________
**Multisig Signers**: ________________

**Contract Addresses**:
- Factory: `0x________________________________________`
- Operator: `0x________________________________________`
- Escrow: `0x________________________________________`

**Configuration**:
- Max Total Fee Rate: _______ bps (_____%)
- Protocol Fee %: _______%
- Fee Recipient: `0x________________________________________`

**Deployment Transactions**:
- Factory Deploy: `0x________________________________________`
- Operator Deploy: `0x________________________________________`
- Ownership Transfer: `0x________________________________________`

**Verification**:
- Basescan Factory: https://basescan.org/address/0x________________
- Basescan Operator: https://basescan.org/address/0x________________

**Sign-offs**:
- Deployer: ________________ (signature) ________________ (date)
- Security Lead: ________________ (signature) ________________ (date)
- Project Lead: ________________ (signature) ________________ (date)

---

**Checklist Version**: 1.0
**Last Updated**: 2026-01-25
