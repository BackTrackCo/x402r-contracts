// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/StaticFeeCalculator.sol";

/**
 * @title DeployProduction
 * @notice Production deployment script with multisig validation
 * @dev Validates owner is a contract (multisig/timelock) before deployment
 *
 * Usage:
 *   source .env.production
 *   forge script script/DeployProduction.s.sol --rpc-url $RPC_URL --broadcast --verify
 *
 * Required Environment Variables:
 *   OWNER_ADDRESS - Multisig address (MUST be contract, not EOA)
 *   ESCROW_ADDRESS - AuthCaptureEscrow address
 *   PROTOCOL_FEE_RECIPIENT - Protocol fee recipient address
 *   PROTOCOL_FEE_BPS - Protocol fee in basis points (0 = no protocol fee)
 *   FEE_RECIPIENT - Operator fee recipient address
 *   FEE_CALCULATOR - Operator fee calculator address (or 0x0 for no operator fee)
 *   AUTHORIZE_CONDITION - Authorize condition address (or 0x0)
 *   AUTHORIZE_RECORDER - Authorize recorder address (or 0x0)
 *   CHARGE_CONDITION - Charge condition address (or 0x0)
 *   CHARGE_RECORDER - Charge recorder address (or 0x0)
 *   RELEASE_CONDITION - Release condition address (or 0x0)
 *   RELEASE_RECORDER - Release recorder address (or 0x0)
 *   REFUND_IN_ESCROW_CONDITION - Refund in escrow condition address (or 0x0)
 *   REFUND_IN_ESCROW_RECORDER - Refund in escrow recorder address (or 0x0)
 *   REFUND_POST_ESCROW_CONDITION - Refund post escrow condition address (or 0x0)
 *   REFUND_POST_ESCROW_RECORDER - Refund post escrow recorder address (or 0x0)
 */
contract DeployProduction is Script {
    function run() external {
        // Load configuration from environment
        address owner = vm.envAddress("OWNER_ADDRESS");
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        uint256 protocolFeeBps = vm.envUint("PROTOCOL_FEE_BPS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address feeCalculator = vm.envOr("FEE_CALCULATOR", address(0));

        console.log("\n=== PRODUCTION DEPLOYMENT ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);

        // CRITICAL VALIDATION: Ensure owner is a contract (multisig/timelock)
        _validateOwnerIsMultisig(owner);

        // Validate configuration
        _validateConfiguration(escrow, protocolFeeRecipient, feeRecipient);

        // Build condition configuration
        PaymentOperator.ConditionConfig memory conditionConfig = _buildConditionConfig();

        // Deploy
        console.log("\n--- Deploying Modular Fee System ---");
        vm.startBroadcast();

        // Deploy protocol fee calculator (if > 0 bps)
        address calculatorAddr = address(0);
        if (protocolFeeBps > 0) {
            StaticFeeCalculator calculator = new StaticFeeCalculator(protocolFeeBps);
            calculatorAddr = address(calculator);
            console.log("StaticFeeCalculator:", calculatorAddr);
        }

        // Deploy ProtocolFeeConfig
        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(calculatorAddr, protocolFeeRecipient, msg.sender);
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));

        // Deploy factory
        PaymentOperatorFactory factory = new PaymentOperatorFactory(escrow, address(protocolFeeConfig));

        console.log("Factory deployed:", address(factory));

        PaymentOperatorFactory.OperatorConfig memory operatorConfig = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: feeRecipient,
            feeCalculator: feeCalculator,
            authorizeCondition: conditionConfig.authorizeCondition,
            authorizeRecorder: conditionConfig.authorizeRecorder,
            chargeCondition: conditionConfig.chargeCondition,
            chargeRecorder: conditionConfig.chargeRecorder,
            releaseCondition: conditionConfig.releaseCondition,
            releaseRecorder: conditionConfig.releaseRecorder,
            refundInEscrowCondition: conditionConfig.refundInEscrowCondition,
            refundInEscrowRecorder: conditionConfig.refundInEscrowRecorder,
            refundPostEscrowCondition: conditionConfig.refundPostEscrowCondition,
            refundPostEscrowRecorder: conditionConfig.refundPostEscrowRecorder
        });

        address operatorAddress = factory.deployOperator(operatorConfig);
        PaymentOperator operator = PaymentOperator(payable(operatorAddress));

        console.log("PaymentOperator deployed:", address(operator));

        // Transfer ProtocolFeeConfig ownership to multisig
        protocolFeeConfig.transferOwnership(owner);

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("\n--- Post-Deployment Verification ---");
        _verifyDeployment(factory, operator, escrow, feeRecipient, address(protocolFeeConfig));

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("\nNext Steps:");
        console.log("1. Complete ProtocolFeeConfig ownership transfer (2-step):");
        console.log("   Call requestOwnershipHandover() from multisig, then completeOwnershipHandover()");
        console.log("2. Verify contracts on block explorer");
    }

    function _validateOwnerIsMultisig(address owner) internal view {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(owner)
        }

        if (codeSize == 0) {
            console.log("\n=== DEPLOYMENT FAILED ===");
            console.log("ERROR: Owner is an EOA, not a multisig contract");
            console.log("Owner address:", owner);
            console.log("\nProduction deployments MUST use multisig owner.");
            revert("DEPLOYMENT FAILED: Owner must be multisig contract, not EOA");
        }

        console.log("[OK] Owner is contract (multisig/timelock verified)");

        try this.isGnosisSafe(owner) returns (bool isSafe) {
            if (isSafe) {
                console.log("[OK] Owner appears to be Gnosis Safe");
            } else {
                console.log("[WARN] Owner is contract but not Gnosis Safe - verify manually");
            }
        } catch {
            console.log("[WARN] Could not detect multisig type - verify manually");
        }
    }

    function isGnosisSafe(address addr) external view returns (bool) {
        (bool success, bytes memory data) = addr.staticcall(abi.encodeWithSignature("getOwners()"));
        if (success && data.length > 0) {
            address[] memory owners = abi.decode(data, (address[]));
            console.log("   Detected Gnosis Safe with", owners.length, "owners");
            return true;
        }
        return false;
    }

    function _validateConfiguration(address escrow, address protocolFeeRecipient, address feeRecipient) internal pure {
        require(escrow != address(0), "Invalid escrow address");
        require(protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
        require(feeRecipient != address(0), "Invalid fee recipient");
    }

    function _buildConditionConfig() internal view returns (PaymentOperator.ConditionConfig memory) {
        return PaymentOperator.ConditionConfig({
            authorizeCondition: vm.envAddress("AUTHORIZE_CONDITION"),
            authorizeRecorder: vm.envAddress("AUTHORIZE_RECORDER"),
            chargeCondition: vm.envAddress("CHARGE_CONDITION"),
            chargeRecorder: vm.envAddress("CHARGE_RECORDER"),
            releaseCondition: vm.envAddress("RELEASE_CONDITION"),
            releaseRecorder: vm.envAddress("RELEASE_RECORDER"),
            refundInEscrowCondition: vm.envAddress("REFUND_IN_ESCROW_CONDITION"),
            refundInEscrowRecorder: vm.envAddress("REFUND_IN_ESCROW_RECORDER"),
            refundPostEscrowCondition: vm.envAddress("REFUND_POST_ESCROW_CONDITION"),
            refundPostEscrowRecorder: vm.envAddress("REFUND_POST_ESCROW_RECORDER")
        });
    }

    function _verifyDeployment(
        PaymentOperatorFactory factory,
        PaymentOperator operator,
        address expectedEscrow,
        address expectedFeeRecipient,
        address expectedProtocolFeeConfig
    ) internal view {
        require(address(operator.ESCROW()) == expectedEscrow, "Escrow mismatch");
        require(operator.FEE_RECIPIENT() == expectedFeeRecipient, "Fee recipient mismatch");
        require(address(operator.PROTOCOL_FEE_CONFIG()) == expectedProtocolFeeConfig, "ProtocolFeeConfig mismatch");
        require(address(operator.ESCROW()) != address(0), "Escrow not set");
        require(operator.FEE_RECIPIENT() != address(0), "Fee recipient not set");

        console.log("[OK] Escrow:", address(operator.ESCROW()));
        console.log("[OK] Fee Recipient:", operator.FEE_RECIPIENT());
        console.log("[OK] ProtocolFeeConfig:", address(operator.PROTOCOL_FEE_CONFIG()));
        console.log("[OK] Factory PROTOCOL_FEE_CONFIG:", factory.PROTOCOL_FEE_CONFIG());
        console.log("\n[OK] All deployment checks passed");
    }
}
