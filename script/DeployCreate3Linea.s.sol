// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Core (commerce-payments)
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Protocol infrastructure
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";

// Singletons
import {ArbiterRegistry} from "../src/registry/ArbiterRegistry.sol";
import {SignatureConditionFactory} from "../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";

// Condition singletons
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";

// Chain-specific conditions
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

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

// Additional
import {RefundRequestConditionFactory} from "../src/requests/refund/RefundRequestConditionFactory.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {RefundRequestEvidence} from "../src/evidence/RefundRequestEvidence.sol";

/// @notice Minimal interface for CreateX's CREATE3 deployment
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/**
 * @title DeployCreate3Linea
 * @notice Deploys remaining 17 contracts on Linea where the first 4 are already deployed.
 *         Hardcodes the already-deployed addresses and only deploys the missing ones.
 *
 * Usage:
 *   USDC_ADDRESS=0x176211869cA2b568f2A7D4EE941E073a821EE1ff TVL_LIMIT=100000000000 \
 *   forge script script/DeployCreate3Linea.s.sol --rpc-url linea --broadcast --verify -vvvv
 */
contract DeployCreate3Linea is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        uint256 tvlLimit = vm.envUint("TVL_LIMIT");

        // Already deployed on Linea at correct CREATE3 addresses
        address escrow = 0xe050bB89eD43BB02d71343063824614A7fb80B77;

        console.log("\n========================================");
        console.log("  x402r CREATE3 Linea (remaining 17)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPk));
        console.log("USDC:", usdcAddress);
        console.log("TVL Limit:", tvlLimit);
        console.log("Escrow (already deployed):", escrow);

        vm.startBroadcast(deployerPk);

        // --- 3. Singletons ---
        console.log("\n--- Singletons ---");

        address sigCondFactory = _deploy3("sig-condition-factory", type(SignatureConditionFactory).creationCode);
        console.log("SignatureConditionFactory:", sigCondFactory);

        address arbiterRegistry = _deploy3("arbiter-registry", type(ArbiterRegistry).creationCode);
        console.log("ArbiterRegistry:", arbiterRegistry);

        address refundReqCondFactory =
            _deploy3("refund-request-condition-factory", type(RefundRequestConditionFactory).creationCode);
        console.log("RefundRequestConditionFactory:", refundReqCondFactory);

        // --- 4. Condition Singletons ---
        console.log("\n--- Condition Singletons ---");

        address payerCondition = _deploy3("payer-condition", type(PayerCondition).creationCode);
        console.log("PayerCondition:", payerCondition);

        address receiverCondition = _deploy3("receiver-condition", type(ReceiverCondition).creationCode);
        console.log("ReceiverCondition:", receiverCondition);

        address alwaysTrueCondition = _deploy3("always-true-condition", type(AlwaysTrueCondition).creationCode);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);

        address usdcTvlLimit = _deploy3(
            "usdc-tvl-limit",
            abi.encodePacked(type(UsdcTvlLimit).creationCode, abi.encode(escrow, usdcAddress, tvlLimit))
        );
        console.log("UsdcTvlLimit:", usdcTvlLimit);

        // --- 5. Factories ---
        console.log("\n--- Factories ---");

        address escrowPeriodFactory = _deploy3(
            "escrow-period-factory", abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(escrow))
        );
        console.log("EscrowPeriodFactory:", escrowPeriodFactory);

        address freezeFactory =
            _deploy3("freeze-factory", abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(escrow)));
        console.log("FreezeFactory:", freezeFactory);

        address staticFeeCalcFactory =
            _deploy3("static-fee-calc-factory", type(StaticFeeCalculatorFactory).creationCode);
        console.log("StaticFeeCalculatorFactory:", staticFeeCalcFactory);

        address staticAddrCondFactory =
            _deploy3("static-addr-condition-factory", type(StaticAddressConditionFactory).creationCode);
        console.log("StaticAddressConditionFactory:", staticAddrCondFactory);

        address andFactory = _deploy3("and-condition-factory", type(AndConditionFactory).creationCode);
        console.log("AndConditionFactory:", andFactory);

        address orFactory = _deploy3("or-condition-factory", type(OrConditionFactory).creationCode);
        console.log("OrConditionFactory:", orFactory);

        address notFactory = _deploy3("not-condition-factory", type(NotConditionFactory).creationCode);
        console.log("NotConditionFactory:", notFactory);

        address recorderCombFactory =
            _deploy3("recorder-combinator-factory", type(RecorderCombinatorFactory).creationCode);
        console.log("RecorderCombinatorFactory:", recorderCombFactory);

        // --- 6. Additional ---
        console.log("\n--- Additional ---");

        address receiverRefundCollector = _deploy3(
            "receiver-refund-collector",
            abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(escrow))
        );
        console.log("ReceiverRefundCollector:", receiverRefundCollector);

        address refundRequestEvidence = _deploy3(
            "refund-request-evidence",
            abi.encodePacked(type(RefundRequestEvidence).creationCode, abi.encode(refundReqCondFactory))
        );
        console.log("RefundRequestEvidence:", refundRequestEvidence);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  LINEA DEPLOYMENT COMPLETE");
        console.log("========================================");
    }

    function _deploy3(string memory label, bytes memory initCode) internal returns (address deployed) {
        bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(label)))));
        deployed = CREATEX.deployCreate3(salt, initCode);
    }
}
