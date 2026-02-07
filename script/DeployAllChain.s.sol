// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Core (commerce-payments)
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

// Protocol infrastructure
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";

// Singletons
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";
import {ArbiterRegistry} from "../src/registry/ArbiterRegistry.sol";
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

// Condition singletons
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";

// Factories
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";
import {
    StaticAddressConditionFactory
} from "../src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {RecorderCombinatorFactory} from "../src/plugins/recorders/combinators/RecorderCombinatorFactory.sol";

/**
 * @title DeployAllChain
 * @notice Full deployment of all x402r contracts to a new chain
 * @dev Deploys everything: escrow, collectors, factories, singletons, conditions.
 *
 * Usage:
 *   USDC_ADDRESS=0x... TVL_LIMIT=100000000000 \
 *   forge script script/DeployAllChain.s.sol --rpc-url <RPC> --broadcast --private-key <KEY> -vvvv
 *
 * Environment Variables:
 *   USDC_ADDRESS - USDC token address on this chain
 *   TVL_LIMIT - Max USDC in escrow (smallest units, e.g., 100000000000 = $100k)
 *   OWNER_ADDRESS - Owner for ProtocolFeeConfig (defaults to deployer)
 *   PROTOCOL_FEE_RECIPIENT - Fee recipient (defaults to deployer)
 *   PROTOCOL_FEE_BPS - Protocol fee in basis points (defaults to 0)
 */
contract DeployAllChain is Script {
    // Multicall3 canonical address (same on all chains)
    address constant DEFAULT_MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    function run() external {
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        address protocolFeeRecipient = vm.envOr("PROTOCOL_FEE_RECIPIENT", msg.sender);
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        uint256 tvlLimit = vm.envUint("TVL_LIMIT");

        console.log("\n========================================");
        console.log("  x402r Full Chain Deployment");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);
        console.log("USDC:", usdcAddress);
        console.log("TVL Limit:", tvlLimit);
        console.log("TVL Limit ($):", tvlLimit / 1e6);

        vm.startBroadcast();

        // =============================================
        // 1. Core (commerce-payments)
        // =============================================
        console.log("\n--- 1. Core Contracts ---");

        AuthCaptureEscrow escrow = new AuthCaptureEscrow();
        console.log("AuthCaptureEscrow:", address(escrow));

        ERC3009PaymentCollector tokenCollector = new ERC3009PaymentCollector(address(escrow), DEFAULT_MULTICALL3);
        console.log("TokenCollector:", address(tokenCollector));

        // =============================================
        // 2. Protocol Infrastructure
        // =============================================
        console.log("\n--- 2. Protocol Infrastructure ---");

        address calculatorAddr = address(0);
        if (protocolFeeBps > 0) {
            StaticFeeCalculator calculator = new StaticFeeCalculator(protocolFeeBps);
            calculatorAddr = address(calculator);
            console.log("StaticFeeCalculator:", calculatorAddr);
        }

        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(calculatorAddr, protocolFeeRecipient, owner);
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));

        PaymentOperatorFactory paymentOperatorFactory =
            new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        console.log("PaymentOperatorFactory:", address(paymentOperatorFactory));

        // =============================================
        // 3. Singletons
        // =============================================
        console.log("\n--- 3. Singletons ---");

        RefundRequest refundRequest = new RefundRequest();
        console.log("RefundRequest:", address(refundRequest));

        ArbiterRegistry arbiterRegistry = new ArbiterRegistry();
        console.log("ArbiterRegistry:", address(arbiterRegistry));

        UsdcTvlLimit usdcTvlLimit = new UsdcTvlLimit(address(escrow), usdcAddress, tvlLimit);
        console.log("UsdcTvlLimit:", address(usdcTvlLimit));

        // =============================================
        // 4. Condition Singletons
        // =============================================
        console.log("\n--- 4. Condition Singletons ---");

        PayerCondition payerCondition = new PayerCondition();
        console.log("PayerCondition:", address(payerCondition));

        ReceiverCondition receiverCondition = new ReceiverCondition();
        console.log("ReceiverCondition:", address(receiverCondition));

        AlwaysTrueCondition alwaysTrueCondition = new AlwaysTrueCondition();
        console.log("AlwaysTrueCondition:", address(alwaysTrueCondition));

        // =============================================
        // 5. Factories
        // =============================================
        console.log("\n--- 5. Factories ---");

        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        console.log("EscrowPeriodFactory:", address(escrowPeriodFactory));

        FreezeFactory freezeFactory = new FreezeFactory(address(escrow));
        console.log("FreezeFactory:", address(freezeFactory));

        StaticFeeCalculatorFactory staticFeeCalcFactory = new StaticFeeCalculatorFactory();
        console.log("StaticFeeCalculatorFactory:", address(staticFeeCalcFactory));

        StaticAddressConditionFactory staticAddrCondFactory = new StaticAddressConditionFactory();
        console.log("StaticAddressConditionFactory:", address(staticAddrCondFactory));

        AndConditionFactory andFactory = new AndConditionFactory();
        console.log("AndConditionFactory:", address(andFactory));

        OrConditionFactory orFactory = new OrConditionFactory();
        console.log("OrConditionFactory:", address(orFactory));

        NotConditionFactory notFactory = new NotConditionFactory();
        console.log("NotConditionFactory:", address(notFactory));

        RecorderCombinatorFactory recorderCombFactory = new RecorderCombinatorFactory();
        console.log("RecorderCombinatorFactory:", address(recorderCombFactory));

        vm.stopBroadcast();

        // =============================================
        // Summary
        // =============================================
        console.log("\n========================================");
        console.log("  DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("authCaptureEscrow:", address(escrow));
        console.log("tokenCollector:", address(tokenCollector));
        console.log("protocolFeeConfig:", address(protocolFeeConfig));
        console.log("refundRequest:", address(refundRequest));
        console.log("arbiterRegistry:", address(arbiterRegistry));
        console.log("usdcTvlLimit:", address(usdcTvlLimit));
        console.log("paymentOperatorFactory:", address(paymentOperatorFactory));
        console.log("escrowPeriodFactory:", address(escrowPeriodFactory));
        console.log("freezeFactory:", address(freezeFactory));
        console.log("staticFeeCalculatorFactory:", address(staticFeeCalcFactory));
        console.log("staticAddressConditionFactory:", address(staticAddrCondFactory));
        console.log("andConditionFactory:", address(andFactory));
        console.log("orConditionFactory:", address(orFactory));
        console.log("notConditionFactory:", address(notFactory));
        console.log("recorderCombinatorFactory:", address(recorderCombFactory));
        console.log("payerCondition:", address(payerCondition));
        console.log("receiverCondition:", address(receiverCondition));
        console.log("alwaysTrueCondition:", address(alwaysTrueCondition));
        console.log("========================================");
    }
}
