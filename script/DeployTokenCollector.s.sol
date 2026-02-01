// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

/**
 * @notice Deploy ERC3009PaymentCollector pointing to existing AuthCaptureEscrow.
 *
 * Required environment variables:
 *   ESCROW_ADDRESS - AuthCaptureEscrow contract address
 *
 * Optional environment variables:
 *   MULTICALL3_ADDRESS - Multicall3 address (defaults to canonical 0xcA11bde05977b3631167028862bE2a173976CA11)
 *
 * Usage (Base Sepolia):
 *   ESCROW_ADDRESS=0xb9488351E48b23D798f24e8174514F28B741Eb4f \
 *   forge script script/DeployTokenCollector.s.sol --rpc-url base-sepolia --broadcast --verify -vvvv
 *
 * Usage (Base Mainnet):
 *   source .env.production
 *   forge script script/DeployTokenCollector.s.sol --rpc-url base --broadcast --verify -vvvv
 */
contract DeployTokenCollector is Script {
    // Multicall3 canonical address (same on all chains)
    address constant DEFAULT_MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    function run() public {
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address multicall3 = vm.envOr("MULTICALL3_ADDRESS", DEFAULT_MULTICALL3);

        console2.log("=== Deploying ERC3009PaymentCollector ===");
        console2.log("Network:", block.chainid);
        console2.log("Escrow:", escrow);
        console2.log("Multicall3:", multicall3);

        vm.startBroadcast();

        ERC3009PaymentCollector collector = new ERC3009PaymentCollector(escrow, multicall3);

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("ERC3009PaymentCollector:", address(collector));
        console2.log("  authCaptureEscrow:", escrow);
        console2.log("  multicall3:", multicall3);
    }
}
