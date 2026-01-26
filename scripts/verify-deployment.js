/**
 * Post-Deployment Verification Script
 *
 * Verifies PaymentOperator deployment configuration and validates
 * that owner is a multisig contract (not EOA).
 *
 * Usage:
 *   OPERATOR_ADDRESS=0x... RPC_URL=https://... node scripts/verify-deployment.js
 */

const { ethers } = require('ethers');

// ABI fragments for verification
const PAYMENT_OPERATOR_ABI = [
  'function owner() view returns (address)',
  'function ESCROW() view returns (address)',
  'function FEE_RECIPIENT() view returns (address)',
  'function MAX_TOTAL_FEE_RATE() view returns (uint256)',
  'function PROTOCOL_FEE_PERCENTAGE() view returns (uint256)',
  'function protocolFeeRecipient() view returns (address)',
  'function feesEnabled() view returns (bool)',
];

const GNOSIS_SAFE_ABI = [
  'function getOwners() view returns (address[])',
  'function getThreshold() view returns (uint256)',
];

async function main() {
  // Get configuration from environment
  const operatorAddress = process.env.OPERATOR_ADDRESS;
  const rpcUrl = process.env.RPC_URL;

  if (!operatorAddress) {
    console.error('❌ ERROR: OPERATOR_ADDRESS not set');
    console.error('Usage: OPERATOR_ADDRESS=0x... RPC_URL=https://... node scripts/verify-deployment.js');
    process.exit(1);
  }

  if (!rpcUrl) {
    console.error('❌ ERROR: RPC_URL not set');
    process.exit(1);
  }

  console.log('\n🔍 Verifying deployment...\n');
  console.log('Operator:', operatorAddress);
  console.log('RPC:', rpcUrl);
  console.log('');

  // Connect to provider
  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // Get contract instance
  const operator = new ethers.Contract(operatorAddress, PAYMENT_OPERATOR_ABI, provider);

  // 1. Verify operator exists
  const code = await provider.getCode(operatorAddress);
  if (code === '0x') {
    console.error('❌ CRITICAL: No contract found at operator address');
    process.exit(1);
  }
  console.log('✅ Operator contract exists');

  // 2. Check owner is contract
  const owner = await operator.owner();
  console.log('\n📋 Owner:', owner);

  const ownerCode = await provider.getCode(owner);
  if (ownerCode === '0x') {
    console.error('❌ CRITICAL: Owner is EOA, not multisig!');
    console.error('   Production deployments MUST use multisig owner');
    process.exit(1);
  }
  console.log('✅ Owner is contract (not EOA)');

  // 3. Try to identify if Gnosis Safe
  const safe = new ethers.Contract(owner, GNOSIS_SAFE_ABI, provider);
  try {
    const threshold = await safe.getThreshold();
    const owners = await safe.getOwners();
    console.log(`✅ Owner is Gnosis Safe ${threshold}/${owners.length} multisig`);
    console.log(`   Signers (${owners.length}):`);
    owners.forEach((signer, i) => {
      console.log(`   ${i + 1}. ${signer}`);
    });
  } catch (error) {
    console.log('⚠️  Owner is contract but not Gnosis Safe');
    console.log('   Manually verify it\'s a multisig or timelock');
  }

  // 4. Verify configuration
  console.log('\n📋 Configuration:');

  const escrow = await operator.ESCROW();
  console.log('   Escrow:', escrow);

  const feeRecipient = await operator.FEE_RECIPIENT();
  console.log('   Fee Recipient:', feeRecipient);

  const maxFeeRate = await operator.MAX_TOTAL_FEE_RATE();
  console.log(`   Max Fee Rate: ${maxFeeRate} bps (${Number(maxFeeRate) / 100}%)`);

  const protocolFeePercentage = await operator.PROTOCOL_FEE_PERCENTAGE();
  console.log(`   Protocol Fee %: ${protocolFeePercentage}%`);

  const protocolFeeRecipient = await operator.protocolFeeRecipient();
  console.log('   Protocol Fee Recipient:', protocolFeeRecipient);

  const feesEnabled = await operator.feesEnabled();
  console.log(`   Fees Enabled: ${feesEnabled}`);

  // 5. Verify immutables are set
  console.log('\n🔒 Immutables:');

  if (escrow === ethers.ZeroAddress) {
    console.error('❌ ERROR: Escrow not set');
    process.exit(1);
  }
  console.log('   ✅ Escrow address set');

  if (feeRecipient === ethers.ZeroAddress) {
    console.error('❌ ERROR: Fee recipient not set');
    process.exit(1);
  }
  console.log('   ✅ Fee recipient set');

  if (maxFeeRate === 0n) {
    console.error('❌ ERROR: Invalid max fee rate (0)');
    process.exit(1);
  }
  console.log('   ✅ Max fee rate valid');

  // 6. Check escrow exists
  const escrowCode = await provider.getCode(escrow);
  if (escrowCode === '0x') {
    console.error('❌ ERROR: Escrow contract not found');
    process.exit(1);
  }
  console.log('   ✅ Escrow contract exists');

  // Summary
  console.log('\n✅ Deployment verification complete!');
  console.log('\nNext steps:');
  console.log('1. Verify contracts on block explorer');
  console.log('2. Update DEPLOYMENT_CHECKLIST.md');
  console.log('3. Test basic operations (view functions)');
  console.log('4. Announce deployment to community');

  // Get chain info
  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);

  let explorerUrl = '';
  if (chainId === 1) explorerUrl = 'https://etherscan.io';
  else if (chainId === 8453) explorerUrl = 'https://basescan.org';
  else if (chainId === 84532) explorerUrl = 'https://sepolia.basescan.org';

  if (explorerUrl) {
    console.log(`\nView on explorer: ${explorerUrl}/address/${operatorAddress}`);
    console.log(`Owner multisig: ${explorerUrl}/address/${owner}`);
  }

  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ Verification failed:', error.message);
    process.exit(1);
  });
