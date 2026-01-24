// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {EscrowPeriodCondition} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodConditionFactory} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodConditionFactory.sol";

/**
 * @title DeployEscrowPeriodCondition
 * @notice Deploys the EscrowPeriodCondition and related contracts
 * @dev This script deploys the EscrowPeriodCondition for time-locked escrow releases.
 *
 *      Environment variables:
 *      - ESCROW_PERIOD: Duration in seconds for escrow lock (required)
 *      - FREEZE_POLICY: Address of freeze policy contract (optional, defaults to address(0) = no freeze support)
 *                       Options:
 *                       - address(0) or empty: No freeze policy (freeze/unfreeze disabled)
 *                       - PayerFreezePolicy address: Only payer can freeze/unfreeze their own payments
 *                       - Custom IFreezePolicy address: Custom authorization logic (must implement IFreezePolicy)
 *
 * ESCROW PERIOD SECURITY GUIDELINES:
 *
 *      MINIMUM RECOMMENDED VALUES:
 *      +-----------------+-------------+------------------+
 *      | Network         | Minimum     | Recommended      |
 *      +-----------------+-------------+------------------+
 *      | L1 (Mainnet)    | 300s (5min) | 900s+ (15min+)   |
 *      | L2 (Base, etc.) | 30s         | 300s+ (5min+)    |
 *      +-----------------+-------------+------------------+
 *
 *      RATIONALE:
 *      - L1: Miners can manipulate block.timestamp by ~15 seconds
 *      - L2: Sequencer controls timestamps (already trusted for tx ordering)
 *
 *      COMMON USE CASES:
 *      - Quick commerce: 300s (5 minutes) - fast checkout with minimal protection
 *      - Standard escrow: 86400s (1 day) - buyer protection window
 *      - Dispute resolution: 604800s (7 days) - full dispute period
 *
 *      WARNING: Escrow periods < 60s on L1 are NOT RECOMMENDED due to timestamp manipulation risks.
 */
contract DeployEscrowPeriodCondition is Script {
    // Minimum recommended escrow periods (in seconds)
    uint256 public constant MIN_ESCROW_PERIOD_L1 = 300; // 5 minutes
    uint256 public constant MIN_ESCROW_PERIOD_L2 = 30; // 30 seconds

    function run() public {
        // Get escrow period from environment
        uint256 escrowPeriod = vm.envUint("ESCROW_PERIOD");

        // Get freeze policy (optional - defaults to address(0) for no freeze support)
        address freezePolicy = vm.envOr("FREEZE_POLICY", address(0));

        // Validate escrow period with warnings
        _validateEscrowPeriod(escrowPeriod);

        vm.startBroadcast();

        console.log("=== Deploying EscrowPeriodCondition ===");
        console.log("Escrow period (seconds):", escrowPeriod);
        console.log("Escrow period (human):", _formatDuration(escrowPeriod));

        if (freezePolicy == address(0)) {
            console.log("\nNo freeze policy (freeze not allowed)");
            console.log("FreezePolicy: address(0) - freeze/unfreeze disabled");
        } else {
            console.log("\nUsing freeze policy:", freezePolicy);
        }

        // Deploy factory and condition instance
        console.log("\nDeploying EscrowPeriodConditionFactory...");
        EscrowPeriodConditionFactory factory = new EscrowPeriodConditionFactory();
        console.log("Factory deployed at:", address(factory));

        console.log("\nDeploying condition via factory...");
        address conditionAddress = factory.deployCondition(escrowPeriod, freezePolicy);

        EscrowPeriodCondition deployedCondition = EscrowPeriodCondition(conditionAddress);

        console.log("\n=== Deployment Summary ===");
        console.log("EscrowPeriodConditionFactory:", address(factory));
        console.log("EscrowPeriodCondition:", conditionAddress);
        console.log("ESCROW_PERIOD:", deployedCondition.ESCROW_PERIOD());
        console.log("FREEZE_POLICY:", address(deployedCondition.FREEZE_POLICY()));

        console.log("\n=== Configuration for ArbitrationOperator ===");
        console.log("CONDITION_FACTORY_ADDRESS=", address(factory));
        console.log("RELEASE_CONDITION=", conditionAddress);

        vm.stopBroadcast();
    }

    function _validateEscrowPeriod(uint256 escrowPeriod) internal view {
        // Determine if we're on L1 or L2 based on chain ID
        uint256 chainId = block.chainid;
        bool isL1 = chainId == 1; // Ethereum mainnet
        uint256 minPeriod = isL1 ? MIN_ESCROW_PERIOD_L1 : MIN_ESCROW_PERIOD_L2;

        if (escrowPeriod < minPeriod) {
            console.log("");
            console.log("!!! WARNING: ESCROW PERIOD BELOW RECOMMENDED MINIMUM !!!");
            console.log("Current period:", escrowPeriod, "seconds");
            console.log("Minimum recommended:", minPeriod, "seconds");
            if (isL1) {
                console.log("Risk: Miners can manipulate timestamps by ~15 seconds");
            }
            console.log("");
        }

        if (escrowPeriod < 60) {
            console.log("!!! CRITICAL: Escrow period < 60s is NOT RECOMMENDED !!!");
            console.log("This may expose users to timestamp manipulation attacks.");
            console.log("");
        }
    }

    function _formatDuration(uint256 seconds_) internal pure returns (string memory) {
        if (seconds_ >= 86400) {
            return string(abi.encodePacked(_toString(seconds_ / 86400), " days"));
        } else if (seconds_ >= 3600) {
            return string(abi.encodePacked(_toString(seconds_ / 3600), " hours"));
        } else if (seconds_ >= 60) {
            return string(abi.encodePacked(_toString(seconds_ / 60), " minutes"));
        } else {
            return string(abi.encodePacked(_toString(seconds_), " seconds"));
        }
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
