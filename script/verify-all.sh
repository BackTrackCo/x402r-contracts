#!/usr/bin/env bash
# Verify all deployed contracts on block explorers
# Usage: ./script/verify-all.sh
set -euo pipefail

cd "$(dirname "$0")/.."
source .env 2>/dev/null || true

PASS=0
FAIL=0
SKIP=0
ALREADY=0

verify() {
  local chain_id="$1"
  local chain_name="$2"
  local address="$3"
  local contract="$4"
  local constructor_args="${5:-}"

  echo ""
  echo "--- Verifying $contract at $address on $chain_name ($chain_id) ---"

  # Use Etherscan V2 API — single key works for all chains
  local verifier_url="https://api.etherscan.io/v2/api?chainid=$chain_id"
  local cmd="forge verify-contract $address $contract --chain-id $chain_id --verifier-url $verifier_url -e $ETHERSCAN_API_KEY --watch"
  if [ -n "$constructor_args" ]; then
    cmd="$cmd --constructor-args $constructor_args"
  fi

  echo "  CMD: $cmd"
  if output=$(eval "$cmd" 2>&1); then
    if echo "$output" | grep -qi "already verified"; then
      echo "  RESULT: Already verified"
      ALREADY=$((ALREADY + 1))
    else
      echo "  RESULT: SUCCESS"
      echo "$output" | tail -3
      PASS=$((PASS + 1))
    fi
  else
    if echo "$output" | grep -qi "already verified"; then
      echo "  RESULT: Already verified"
      ALREADY=$((ALREADY + 1))
    else
      echo "  RESULT: FAILED"
      echo "$output" | tail -5
      FAIL=$((FAIL + 1))
    fi
  fi
}

encode_args() {
  # ABI-encode constructor args
  cast abi-encode "$@"
}

echo "============================================"
echo "  x402r Contract Verification"
echo "============================================"

# ==========================================
# BASE SEPOLIA (84532)
# ==========================================
echo ""
echo "======== BASE SEPOLIA (84532) ========"

ESCROW=0x29025c0E9D4239d438e169570818dB9FE0A80873
MULTICALL3=0xcA11bde05977b3631167028862bE2a173976CA11
DEPLOYER=0x773dBcB5BDb3Df8359ba4e42D7Ce7AE3fC9Ee235
USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e
TVL=100000000
PROTOCOL_FEE_CONFIG=0x8F96C493bAC365E41f0315cf45830069EBbDCaCe

verify 84532 "Base Sepolia" 0x29025c0E9D4239d438e169570818dB9FE0A80873 \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 84532 "Base Sepolia" 0x5cA789000070DF15b4663DB64a50AeF5D49c5Ee0 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 84532 "Base Sepolia" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 84532 "Base Sepolia" 0x97d53e63A9CB97556c00BeFd325AF810c9b267B2 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 84532 "Base Sepolia" 0x1C2Ab244aC8bDdDB74d43389FF34B118aF2E90F4 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 84532 "Base Sepolia" 0x762d562a5ff10EcbFD2Bc4fea663433b84226F35 \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 84532 "Base Sepolia" 0xc07b00609f0be9C120B502FA84AFE9db346CB2da \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 84532 "Base Sepolia" 0xBda4593E6133036ef9754c9AfC974C761230249D \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 84532 "Base Sepolia" 0x00DCe240b6DDD335F2327c3F6d0E1d3732f5C97b \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 84532 "Base Sepolia" 0x0A427c66C3eC3BF7c3e69238c2D4779a1Bc12c3A \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 84532 "Base Sepolia" 0x34A5AAF8C19e04d0193466bdF80D155EC934c980 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 84532 "Base Sepolia" 0x45B0d8ca06e0367ef99E3535d32abb0074e06bD3 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 84532 "Base Sepolia" 0xD9989E2F2Ac0494119bd1C0f3CABC47D26758659 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 84532 "Base Sepolia" 0xA7C944301a4CdB3f9d6776eB742E0fe24368AF90 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 84532 "Base Sepolia" 0x46F5aF23960F4300e7Fb1ded3742cA5509F6F596 \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 84532 "Base Sepolia" 0xd5adb393a541D1611AdfAf5400cD5AC12941D1dB \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 84532 "Base Sepolia" 0x18BC108e8CB28a68B521e72DA1DA07d507199698 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 84532 "Base Sepolia" 0xa1C0ECD30f2780f617DF88e21664e0ce971fEbB0 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 84532 "Base Sepolia" 0x36a03071bA0D3F09a50381fCA6C9906B69Ba8c0E \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# BASE MAINNET (8453)
# ==========================================
echo ""
echo "======== BASE MAINNET (8453) ========"

ESCROW=0xb9488351E48b23D798f24e8174514F28B741Eb4f
USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
TVL=100000000000
PROTOCOL_FEE_CONFIG=0x59314674BAbb1a24Eb2704468a9cCdD50668a1C6

verify 8453 "Base Mainnet" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 8453 "Base Mainnet" 0x48ADf6E37F9b31dC2AAD0462C5862B5422C736B8 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 8453 "Base Mainnet" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 8453 "Base Mainnet" 0x3D0837fF8Ea36F417261577b9BA568400A840260 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 8453 "Base Mainnet" 0x35fb2EFEfAc3Ee9f6E52A9AAE5C9655bC08dEc00 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 8453 "Base Mainnet" 0xB68C023365EB08021E12f7f7f11a03282443863A \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 8453 "Base Mainnet" 0x67B63Af4bcdCD3E4263d9995aB04563fbC229944 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 8453 "Base Mainnet" 0x7254b68D1AaAbd118C8A8b15756b4654c10a16d2 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 8453 "Base Mainnet" 0x6926c05193c714ED4bA3867Ee93d6816Fdc14128 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 8453 "Base Mainnet" 0xBAF68176FF94CAdD403EF7FbB776bbca548AC09D \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 8453 "Base Mainnet" 0x12EDefd4549c53497689067f165c0f101796Eb6D \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 8453 "Base Mainnet" 0x64b5071C7e1eDA582849DF392a1EBdf78690a90C \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 8453 "Base Mainnet" 0x9D4146EF898c8E60B3e865AE254ef438E7cEd2A0 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 8453 "Base Mainnet" 0x206D4DbB6E7b876e4B5EFAAD2a04e7d7813FB6ba \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 8453 "Base Mainnet" 0x5b3e33791C1764cF7e2573Bf8116F1D361FD97Cd \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 8453 "Base Mainnet" 0x1e52a74cE6b69F04a506eF815743E1052A1BD28F \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 8453 "Base Mainnet" 0xFa8C4Cb156053b867Ae7489220A29b5939E3Df70 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 8453 "Base Mainnet" 0xEb0C15bE3F77193324844340899C20c44771d53C \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 8453 "Base Mainnet" 0x4bDb9ccC91CA63cfedb6CB0dbf21BC6dD562bb04 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# ETHEREUM SEPOLIA (11155111)
# ==========================================
echo ""
echo "======== ETHEREUM SEPOLIA (11155111) ========"

ESCROW=0x320a3c35F131E5D2Fb36af56345726B298936037
USDC=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
TVL=100000000
PROTOCOL_FEE_CONFIG=0xD979dBfBdA5f4b16AAF60Eaab32A44f352076838

verify 11155111 "Ethereum Sepolia" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 11155111 "Ethereum Sepolia" 0x230fd3A171750FA45db2976121376b7F47Cba308 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 11155111 "Ethereum Sepolia" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 11155111 "Ethereum Sepolia" 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 11155111 "Ethereum Sepolia" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 11155111 "Ethereum Sepolia" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 11155111 "Ethereum Sepolia" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 11155111 "Ethereum Sepolia" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 11155111 "Ethereum Sepolia" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 11155111 "Ethereum Sepolia" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 11155111 "Ethereum Sepolia" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 11155111 "Ethereum Sepolia" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 11155111 "Ethereum Sepolia" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 11155111 "Ethereum Sepolia" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 11155111 "Ethereum Sepolia" 0xAfdEEa8f37AC2cfaE6732c31FEde0A014BfD693a \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 11155111 "Ethereum Sepolia" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 11155111 "Ethereum Sepolia" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 11155111 "Ethereum Sepolia" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 11155111 "Ethereum Sepolia" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# ETHEREUM MAINNET (1)
# ==========================================
echo ""
echo "======== ETHEREUM MAINNET (1) ========"

ESCROW=0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98
USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8

# From DeployAllChain
verify 1 "Ethereum Mainnet" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 1 "Ethereum Mainnet" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 1 "Ethereum Mainnet" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 1 "Ethereum Mainnet" 0x48ADf6E37F9b31dC2AAD0462C5862B5422C736B8 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 1 "Ethereum Mainnet" 0x59314674BAbb1a24Eb2704468a9cCdD50668a1C6 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 1 "Ethereum Mainnet" 0x3D0837fF8Ea36F417261577b9BA568400A840260 \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 1 "Ethereum Mainnet" 0x35fb2EFEfAc3Ee9f6E52A9AAE5C9655bC08dEc00 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 1 "Ethereum Mainnet" 0xB68C023365EB08021E12f7f7f11a03282443863A \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 1 "Ethereum Mainnet" 0x67B63Af4bcdCD3E4263d9995aB04563fbC229944 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 1 "Ethereum Mainnet" 0x7254b68D1AaAbd118C8A8b15756b4654c10a16d2 \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

# Factories from DeployAllChain
verify 1 "Ethereum Mainnet" 0x6926c05193c714ED4bA3867Ee93d6816Fdc14128 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 1 "Ethereum Mainnet" 0xBAF68176FF94CAdD403EF7FbB776bbca548AC09D \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 1 "Ethereum Mainnet" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 1 "Ethereum Mainnet" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 1 "Ethereum Mainnet" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

# Factories from DeployEthRemaining (used in SDK config)
verify 1 "Ethereum Mainnet" 0x32471d31910A009273a812dE0894D9F0AdeF4834 \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 1 "Ethereum Mainnet" 0xe2659dc0d716B1226DF6a09A5f47862cd1ff6733 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 1 "Ethereum Mainnet" 0x536439b00002CB3c0141391A92aFBB3e1E3f8604 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 1 "Ethereum Mainnet" 0xb9488351E48b23D798f24e8174514F28B741Eb4f \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# POLYGON (137)
# ==========================================
echo ""
echo "======== POLYGON (137) ========"

ESCROW=0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6
USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xE78648e7af7B1BaDE717FF6E410B922F92adE80f

verify 137 "Polygon" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 137 "Polygon" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 137 "Polygon" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 137 "Polygon" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 137 "Polygon" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 137 "Polygon" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 137 "Polygon" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 137 "Polygon" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 137 "Polygon" 0x26A3d27139b442Be5ECc10c8608c494627B660BF \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 137 "Polygon" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 137 "Polygon" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 137 "Polygon" 0xCAEd9474c06bf9139AC36C874dED838e1Bcb9310 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 137 "Polygon" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 137 "Polygon" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 137 "Polygon" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 137 "Polygon" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 137 "Polygon" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 137 "Polygon" 0xd709e87DF198eF3C15C5eaE81E3EbD8Fd7AC908a \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 137 "Polygon" 0x9B16ff5bcF5C0B2c31Cd17032a306E91CA67F546 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# ARBITRUM (42161)
# ==========================================
echo ""
echo "======== ARBITRUM (42161) ========"

ESCROW=0x320a3c35F131E5D2Fb36af56345726B298936037
USDC=0xaf88d065e77c8cC2239327C5EDb3A432268e5831
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xD979dBfBdA5f4b16AAF60Eaab32A44f352076838

verify 42161 "Arbitrum" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 42161 "Arbitrum" 0x230fd3A171750FA45db2976121376b7F47Cba308 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 42161 "Arbitrum" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 42161 "Arbitrum" 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 42161 "Arbitrum" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 42161 "Arbitrum" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 42161 "Arbitrum" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 42161 "Arbitrum" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 42161 "Arbitrum" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 42161 "Arbitrum" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 42161 "Arbitrum" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 42161 "Arbitrum" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 42161 "Arbitrum" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 42161 "Arbitrum" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 42161 "Arbitrum" 0xAfdEEa8f37AC2cfaE6732c31FEde0A014BfD693a \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 42161 "Arbitrum" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 42161 "Arbitrum" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 42161 "Arbitrum" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 42161 "Arbitrum" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# CELO (42220)
# ==========================================
echo ""
echo "======== CELO (42220) ========"

ESCROW=0x320a3c35F131E5D2Fb36af56345726B298936037
USDC=0xcebA9300f2b948710d2653dD7B07f33A8B32118C
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xD979dBfBdA5f4b16AAF60Eaab32A44f352076838

verify 42220 "Celo" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 42220 "Celo" 0x230fd3A171750FA45db2976121376b7F47Cba308 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 42220 "Celo" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 42220 "Celo" 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 42220 "Celo" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 42220 "Celo" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 42220 "Celo" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 42220 "Celo" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 42220 "Celo" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 42220 "Celo" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 42220 "Celo" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 42220 "Celo" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 42220 "Celo" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 42220 "Celo" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 42220 "Celo" 0xAfdEEa8f37AC2cfaE6732c31FEde0A014BfD693a \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 42220 "Celo" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 42220 "Celo" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 42220 "Celo" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 42220 "Celo" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# AVALANCHE (43114)
# ==========================================
echo ""
echo "======== AVALANCHE (43114) ========"

ESCROW=0x320a3c35F131E5D2Fb36af56345726B298936037
USDC=0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xD979dBfBdA5f4b16AAF60Eaab32A44f352076838

verify 43114 "Avalanche" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 43114 "Avalanche" 0x230fd3A171750FA45db2976121376b7F47Cba308 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 43114 "Avalanche" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 43114 "Avalanche" 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 43114 "Avalanche" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 43114 "Avalanche" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 43114 "Avalanche" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 43114 "Avalanche" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 43114 "Avalanche" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 43114 "Avalanche" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 43114 "Avalanche" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 43114 "Avalanche" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 43114 "Avalanche" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 43114 "Avalanche" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 43114 "Avalanche" 0xAfdEEa8f37AC2cfaE6732c31FEde0A014BfD693a \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 43114 "Avalanche" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 43114 "Avalanche" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 43114 "Avalanche" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 43114 "Avalanche" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# OPTIMISM (10)
# ==========================================
echo ""
echo "======== OPTIMISM (10) ========"

ESCROW=0x320a3c35F131E5D2Fb36af56345726B298936037
USDC=0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85
TVL=100000000000
PROTOCOL_FEE_CONFIG=0xD979dBfBdA5f4b16AAF60Eaab32A44f352076838

verify 10 "Optimism" $ESCROW \
  "lib/commerce-payments/src/AuthCaptureEscrow.sol:AuthCaptureEscrow"

verify 10 "Optimism" 0x230fd3A171750FA45db2976121376b7F47Cba308 \
  "lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol:ERC3009PaymentCollector" \
  "$(encode_args 'constructor(address,address)' $ESCROW $MULTICALL3)"

verify 10 "Optimism" $PROTOCOL_FEE_CONFIG \
  "src/plugins/fees/ProtocolFeeConfig.sol:ProtocolFeeConfig" \
  "$(encode_args 'constructor(address,address,address)' 0x0000000000000000000000000000000000000000 $DEPLOYER $DEPLOYER)"

verify 10 "Optimism" 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6 \
  "src/operator/PaymentOperatorFactory.sol:PaymentOperatorFactory" \
  "$(encode_args 'constructor(address,address)' $ESCROW $PROTOCOL_FEE_CONFIG)"

verify 10 "Optimism" 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98 \
  "src/requests/refund/RefundRequest.sol:RefundRequest"

verify 10 "Optimism" 0xE78648e7af7B1BaDE717FF6E410B922F92adE80f \
  "src/registry/ArbiterRegistry.sol:ArbiterRegistry"

verify 10 "Optimism" 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8 \
  "src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol:UsdcTvlLimit" \
  "$(encode_args 'constructor(address,address,uint256)' $ESCROW $USDC $TVL)"

verify 10 "Optimism" 0xed02d3E5167BCc9582D851885A89b050AB816a56 \
  "src/plugins/conditions/access/PayerCondition.sol:PayerCondition"

verify 10 "Optimism" 0xc9BbA6A2CF9838e7Dd8c19BC8B3BAC620B9D8178 \
  "src/plugins/conditions/access/ReceiverCondition.sol:ReceiverCondition"

verify 10 "Optimism" 0x46C44071BDf9753482400B76d88A5850318b776F \
  "src/plugins/conditions/access/AlwaysTrueCondition.sol:AlwaysTrueCondition"

verify 10 "Optimism" 0x2714EA3e839Ac50F52B2e2a5788F614cACeE5316 \
  "src/plugins/escrow-period/EscrowPeriodFactory.sol:EscrowPeriodFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 10 "Optimism" 0xA50F51254E8B08899EdB76Bd24b4DC6A61ba7dE7 \
  "src/plugins/freeze/FreezeFactory.sol:FreezeFactory" \
  "$(encode_args 'constructor(address)' $ESCROW)"

verify 10 "Optimism" 0x89257cA1114139C3332bb73655BC2e4C924aC678 \
  "src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol:StaticFeeCalculatorFactory"

verify 10 "Optimism" 0x0DdF51E62DDD41B5f67BEaF2DCE9F2E99E2C5aF5 \
  "src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol:StaticAddressConditionFactory"

verify 10 "Optimism" 0xAfdEEa8f37AC2cfaE6732c31FEde0A014BfD693a \
  "src/plugins/conditions/combinators/AndConditionFactory.sol:AndConditionFactory"

verify 10 "Optimism" 0xe968AA7530b9C3336FED14FD5D5D4dD3Cf82655D \
  "src/plugins/conditions/combinators/OrConditionFactory.sol:OrConditionFactory"

verify 10 "Optimism" 0xc5a96DaBd3F0E485CEEA7Bf912fC5834A6DE2267 \
  "src/plugins/conditions/combinators/NotConditionFactory.sol:NotConditionFactory"

verify 10 "Optimism" 0x6a7E26c3A78a7B1eFF9Dd28d51B2a15df3208B84 \
  "src/plugins/recorders/combinators/RecorderCombinatorFactory.sol:RecorderCombinatorFactory"

verify 10 "Optimism" 0x19a798c7F66E6401f6004b732dA604196952e843 \
  "src/collectors/ReceiverRefundCollector.sol:ReceiverRefundCollector" \
  "$(encode_args 'constructor(address)' $ESCROW)"


# ==========================================
# SUMMARY
# ==========================================
echo ""
echo "============================================"
echo "  VERIFICATION SUMMARY"
echo "============================================"
echo "  Passed:           $PASS"
echo "  Already verified: $ALREADY"
echo "  Failed:           $FAIL"
echo "  Total:            $((PASS + ALREADY + FAIL))"
echo "============================================"
