// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Protocol infrastructure
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";

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

/**
 * @title DeployEthMainnetRedeploy
 * @notice Redeploy unverified contracts on Ethereum Mainnet
 * @dev Redeploys contracts that failed verification due to code version mismatch.
 *      AuthCaptureEscrow, TokenCollector, ProtocolFeeConfig, and all combinator factories
 *      are already verified and do NOT need redeployment.
 *
 * Usage:
 *   forge script script/DeployEthMainnetRedeploy.s.sol \
 *     --rpc-url <ETH_RPC> --broadcast -vvvv
 */
contract DeployEthMainnetRedeploy is Script {
    // Already deployed and verified on Ethereum Mainnet
    address constant ESCROW = 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98;
    address constant PROTOCOL_FEE_CONFIG = 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 constant TVL_LIMIT = 100_000_000_000; // $100k in USDC smallest units

    function run() external {
        console.log("\n========================================");
        console.log("  Ethereum Mainnet Redeploy");
        console.log("========================================");
        console.log("Escrow:", ESCROW);
        console.log("ProtocolFeeConfig:", PROTOCOL_FEE_CONFIG);
        console.log("USDC:", USDC);

        vm.startBroadcast();

        // --- Singletons ---
        PaymentOperatorFactory paymentOperatorFactory = new PaymentOperatorFactory(ESCROW, PROTOCOL_FEE_CONFIG);
        console.log("PaymentOperatorFactory:", address(paymentOperatorFactory));

        RefundRequest refundRequest = new RefundRequest();
        console.log("RefundRequest:", address(refundRequest));

        ArbiterRegistry arbiterRegistry = new ArbiterRegistry();
        console.log("ArbiterRegistry:", address(arbiterRegistry));

        UsdcTvlLimit usdcTvlLimit = new UsdcTvlLimit(ESCROW, USDC, TVL_LIMIT);
        console.log("UsdcTvlLimit:", address(usdcTvlLimit));

        // --- Condition Singletons ---
        PayerCondition payerCondition = new PayerCondition();
        console.log("PayerCondition:", address(payerCondition));

        ReceiverCondition receiverCondition = new ReceiverCondition();
        console.log("ReceiverCondition:", address(receiverCondition));

        AlwaysTrueCondition alwaysTrueCondition = new AlwaysTrueCondition();
        console.log("AlwaysTrueCondition:", address(alwaysTrueCondition));

        // --- Factories ---
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(ESCROW);
        console.log("EscrowPeriodFactory:", address(escrowPeriodFactory));

        FreezeFactory freezeFactory = new FreezeFactory(ESCROW);
        console.log("FreezeFactory:", address(freezeFactory));

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  REDEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("paymentOperatorFactory:", address(paymentOperatorFactory));
        console.log("refundRequest:", address(refundRequest));
        console.log("arbiterRegistry:", address(arbiterRegistry));
        console.log("usdcTvlLimit:", address(usdcTvlLimit));
        console.log("payerCondition:", address(payerCondition));
        console.log("receiverCondition:", address(receiverCondition));
        console.log("alwaysTrueCondition:", address(alwaysTrueCondition));
        console.log("escrowPeriodFactory:", address(escrowPeriodFactory));
        console.log("freezeFactory:", address(freezeFactory));
        console.log("========================================");
    }
}
