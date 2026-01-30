// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";

/**
 * @title DeployProduction
 * @notice Production deployment script - deploys factory only
 * @dev Validates owner is a contract (multisig/timelock) before deployment
 *      Operators are deployed on-demand via factory.deployOperator()
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
 */
contract DeployProduction is Script {
    function run() external {
        // Load configuration from environment
        address owner = vm.envAddress("OWNER_ADDRESS");
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        uint256 protocolFeeBps = vm.envUint("PROTOCOL_FEE_BPS");

        console.log("\n=== PRODUCTION DEPLOYMENT ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);

        // CRITICAL VALIDATION: Ensure owner is a contract (multisig/timelock)
        _validateOwnerIsMultisig(owner);

        // Validate configuration
        _validateConfiguration(escrow, protocolFeeRecipient);

        // Deploy
        console.log("\n--- Deploying Protocol Infrastructure ---");
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

        // Transfer ProtocolFeeConfig ownership to multisig
        protocolFeeConfig.transferOwnership(owner);

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("\n--- Post-Deployment Verification ---");
        _verifyDeployment(factory, escrow, address(protocolFeeConfig));

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Escrow:", escrow);
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));
        console.log("Factory:", address(factory));
        console.log("Owner:", owner);
        console.log("\nOperators deployed on-demand via factory.deployOperator()");
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

    function _validateConfiguration(address escrow, address protocolFeeRecipient) internal pure {
        require(escrow != address(0), "Invalid escrow address");
        require(protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
    }

    function _verifyDeployment(
        PaymentOperatorFactory factory,
        address expectedEscrow,
        address expectedProtocolFeeConfig
    ) internal view {
        require(factory.ESCROW() == expectedEscrow, "Escrow mismatch");
        require(factory.PROTOCOL_FEE_CONFIG() == expectedProtocolFeeConfig, "ProtocolFeeConfig mismatch");

        console.log("[OK] Factory ESCROW:", factory.ESCROW());
        console.log("[OK] Factory PROTOCOL_FEE_CONFIG:", factory.PROTOCOL_FEE_CONFIG());
        console.log("\n[OK] All deployment checks passed");
    }
}
