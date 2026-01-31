// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

/**
 * @notice Deploy ERC3009PaymentCollector pointing to existing AuthCaptureEscrow.
 *
 * Usage:
 * forge script script/DeployTokenCollector.s.sol --rpc-url https://sepolia.base.org --broadcast --verify -vvvv
 */
contract DeployTokenCollector is Script {
    // The correct AuthCaptureEscrow from SDK config
    address constant ESCROW = 0xb9488351E48b23D798f24e8174514F28B741Eb4f;
    // Multicall3 (same on all chains)
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    function run() public {
        vm.startBroadcast();

        ERC3009PaymentCollector collector = new ERC3009PaymentCollector(ESCROW, MULTICALL3);

        vm.stopBroadcast();

        console2.log("Deployed ERC3009PaymentCollector:", address(collector));
        console2.log("  authCaptureEscrow:", ESCROW);
        console2.log("  multicall3:", MULTICALL3);
    }
}
