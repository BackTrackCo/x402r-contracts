// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

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
 *   MAX_TOTAL_FEE_RATE - Maximum total fee rate in basis points
 *   PROTOCOL_FEE_PERCENTAGE - Protocol fee percentage (0-100)
 *   FEE_RECIPIENT - Operator fee recipient address
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
        uint256 maxTotalFeeRate = vm.envUint("MAX_TOTAL_FEE_RATE");
        uint256 protocolFeePercentage = vm.envUint("PROTOCOL_FEE_PERCENTAGE");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("\n=== PRODUCTION DEPLOYMENT ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);

        // CRITICAL VALIDATION: Ensure owner is a contract (multisig/timelock)
        _validateOwnerIsMultisig(owner);

        // Validate configuration
        _validateConfiguration(escrow, protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, feeRecipient);

        // Build condition configuration
        PaymentOperator.ConditionConfig memory conditionConfig = _buildConditionConfig();

        // Deploy
        console.log("\n--- Deploying PaymentOperatorFactory ---");
        vm.startBroadcast();

        PaymentOperatorFactory factory = new PaymentOperatorFactory(
            escrow, protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, msg.sender
        );

        console.log("Factory deployed:", address(factory));

        PaymentOperatorFactory.OperatorConfig memory operatorConfig = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: feeRecipient,
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

        // Transfer factory ownership to multisig
        factory.transferOwnership(owner);

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("\n--- Post-Deployment Verification ---");
        _verifyDeployment(factory, operator, owner, escrow, feeRecipient, maxTotalFeeRate, protocolFeePercentage);

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("\nNext Steps:");
        console.log("1. Run post-deployment verification script:");
        console.log("   npx hardhat run scripts/verify-deployment.ts --network <network>");
        console.log("2. Complete ownership transfer (if 2-step):");
        console.log("   Call completeOwnershipHandover() from multisig");
        console.log("3. Verify contracts on block explorer");
        console.log("4. Update DEPLOYMENT_CHECKLIST.md");
        console.log("5. Announce deployment to community\n");
    }

    /**
     * @notice Validate owner is a contract (multisig/timelock), not EOA
     * @dev Critical security check - prevents accidental deployment with EOA owner
     */
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
            console.log("For testnet deployments, use script/DeployTestnet.s.sol");
            revert("DEPLOYMENT FAILED: Owner must be multisig contract, not EOA");
        }

        console.log("[OK] Owner is contract (multisig/timelock verified)");

        // Try to detect Gnosis Safe
        try this.isGnosisSafe(owner) returns (bool isSafe) {
            if (isSafe) {
                console.log("[OK] Owner appears to be Gnosis Safe");
            } else {
                console.log("[WARN]  Owner is contract but not Gnosis Safe - verify manually");
            }
        } catch {
            console.log("[WARN]  Could not detect multisig type - verify manually");
        }
    }

    /**
     * @notice Attempt to detect if address is Gnosis Safe
     * @dev External function to allow try/catch
     */
    function isGnosisSafe(address addr) external view returns (bool) {
        // Try to call getOwners() - Gnosis Safe interface
        (bool success, bytes memory data) = addr.staticcall(abi.encodeWithSignature("getOwners()"));
        if (success && data.length > 0) {
            address[] memory owners = abi.decode(data, (address[]));
            console.log("   Detected Gnosis Safe with", owners.length, "owners");
            return true;
        }
        return false;
    }

    /**
     * @notice Validate deployment configuration
     */
    function _validateConfiguration(
        address escrow,
        address protocolFeeRecipient,
        uint256 maxTotalFeeRate,
        uint256 protocolFeePercentage,
        address feeRecipient
    ) internal pure {
        require(escrow != address(0), "Invalid escrow address");
        require(protocolFeeRecipient != address(0), "Invalid protocol fee recipient");
        require(feeRecipient != address(0), "Invalid fee recipient");
        require(maxTotalFeeRate > 0 && maxTotalFeeRate <= 10000, "Invalid max total fee rate");
        require(protocolFeePercentage <= 100, "Invalid protocol fee percentage");
    }

    /**
     * @notice Build condition configuration from environment
     */
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

    /**
     * @notice Verify deployment was successful
     */
    function _verifyDeployment(
        PaymentOperatorFactory factory,
        PaymentOperator operator,
        address expectedOwner,
        address expectedEscrow,
        address expectedFeeRecipient,
        uint256 expectedMaxFeeRate,
        uint256 expectedProtocolFeePercentage
    ) internal view {
        // Verify operator configuration
        require(address(operator.ESCROW()) == expectedEscrow, "Escrow mismatch");
        require(operator.FEE_RECIPIENT() == expectedFeeRecipient, "Fee recipient mismatch");
        require(operator.MAX_TOTAL_FEE_RATE() == expectedMaxFeeRate, "Max fee rate mismatch");
        require(operator.PROTOCOL_FEE_PERCENTAGE() == expectedProtocolFeePercentage, "Protocol fee % mismatch");

        // Verify immutables are set
        require(address(operator.ESCROW()) != address(0), "Escrow not set");
        require(operator.FEE_RECIPIENT() != address(0), "Fee recipient not set");
        require(operator.MAX_TOTAL_FEE_RATE() > 0, "Invalid fee rate");

        console.log("[OK] Escrow:", address(operator.ESCROW()));
        console.log("[OK] Fee Recipient:", operator.FEE_RECIPIENT());
        console.log("[OK] Max Total Fee Rate:", operator.MAX_TOTAL_FEE_RATE(), "bps");
        console.log("[OK] Protocol Fee %:", operator.PROTOCOL_FEE_PERCENTAGE());

        console.log("\n[OK] All deployment checks passed");
    }
}
