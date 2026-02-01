// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

/**
 * @title DeployUsdcTvlLimit
 * @notice Deploy USDC TVL limiter for early mainnet safety
 * @dev Blocks all non-USDC tokens and limits USDC TVL in escrow.
 *
 * Usage (Base Mainnet - $100k limit):
 *   ESCROW_ADDRESS=0x... \
 *   USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 \
 *   TVL_LIMIT=100000000000 \
 *   forge script script/DeployUsdcTvlLimit.s.sol --rpc-url base --broadcast --verify -vvvv
 *
 * Usage (Base Sepolia):
 *   ESCROW_ADDRESS=0xb9488351E48b23D798f24e8174514F28B741Eb4f \
 *   USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e \
 *   TVL_LIMIT=100000000 \
 *   forge script script/DeployUsdcTvlLimit.s.sol --rpc-url base-sepolia --broadcast --verify -vvvv
 *
 * Environment Variables:
 *   ESCROW_ADDRESS - AuthCaptureEscrow address
 *   USDC_ADDRESS - USDC token address (6 decimals)
 *   TVL_LIMIT - Max USDC in escrow (in smallest units, e.g., 100000000000 = $100k)
 */
contract DeployUsdcTvlLimit is Script {
    // Base Mainnet USDC
    address constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Base Sepolia USDC
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() public {
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address usdc = vm.envOr("USDC_ADDRESS", _defaultUsdc());
        uint256 limit = vm.envUint("TVL_LIMIT");

        console.log("=== Deploying UsdcTvlLimit ===");
        console.log("Network:", block.chainid);
        console.log("Escrow:", escrow);
        console.log("USDC:", usdc);
        console.log("Limit:", limit);
        console.log("Limit ($):", limit / 1e6);

        vm.startBroadcast();

        UsdcTvlLimit tvlLimit = new UsdcTvlLimit(escrow, usdc, limit);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("UsdcTvlLimit:", address(tvlLimit));
        console.log("\nUse this address in operator condition slots to enforce TVL limit.");
    }

    function _defaultUsdc() internal view returns (address) {
        if (block.chainid == 8453) return BASE_MAINNET_USDC;
        if (block.chainid == 84532) return BASE_SEPOLIA_USDC;
        revert("Set USDC_ADDRESS for this network");
    }
}
