// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

/**
 * @title CheckVaultState
 * @notice Diagnostic script to check vault state and identify withdrawal issues
 */
contract CheckVaultState is Script {
    function run() public {
        // Base Mainnet addresses
        address escrowAddress = vm.envOr("ESCROW_ADDRESS", address(0x5cE5a6d6AD87572f359e3a4f9Bfbaea3157987E2));
        address vaultAddress = vm.envOr("VAULT_ADDRESS", address(0x7BfA7C4f149E7415b73bdeDfe609237e29CBF34A));
        
        Escrow escrow = Escrow(escrowAddress);
        IERC4626 vault = IERC4626(vaultAddress);
        
        console.log("=== Vault State Check ===");
        console.log("Escrow address:", address(escrow));
        console.log("Vault address:", address(vault));
        
        // Check vault state
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 vaultTotalSupply = vault.totalSupply();
        uint256 escrowVaultShares = vault.balanceOf(address(escrow));
        uint256 escrowMaxWithdraw = vault.maxWithdraw(address(escrow));
        uint256 escrowTotalPrincipal = escrow.totalPrincipal();
        
        console.log("\n=== Vault Metrics ===");
        console.log("Vault totalAssets:", vaultTotalAssets);
        console.log("Vault totalSupply (shares):", vaultTotalSupply);
        console.log("Escrow vault shares:", escrowVaultShares);
        console.log("Escrow maxWithdraw:", escrowMaxWithdraw);
        console.log("Escrow totalPrincipal:", escrowTotalPrincipal);
        
        // Calculate share price
        if (vaultTotalSupply > 0) {
            uint256 sharePrice = (vaultTotalAssets * 1e18) / vaultTotalSupply;
            console.log("Share price (1e18):", sharePrice);
        }
        
        // Check if there's a discrepancy
        if (escrowMaxWithdraw < escrowTotalPrincipal) {
            console.log("\n!!! WARNING: maxWithdraw < totalPrincipal !!!");
            console.log("This means the vault has lost value or has fees");
            console.log("Difference:", escrowTotalPrincipal - escrowMaxWithdraw);
        } else {
            console.log("\nVault has sufficient assets for all deposits");
            console.log("Excess (potential yield):", escrowMaxWithdraw - escrowTotalPrincipal);
        }
        
        // Check a specific deposit if provided
        address user = vm.envOr("USER_ADDRESS", address(0));
        uint256 depositNonce = vm.envOr("DEPOSIT_NONCE", uint256(0));
        
        if (user != address(0) && depositNonce > 0) {
            console.log("\n=== Specific Deposit Check ===");
            (uint256 principal, , , ) = escrow.getDeposit(user, depositNonce);
            console.log("User:", user);
            console.log("Deposit nonce:", depositNonce);
            console.log("Principal:", principal);
            
            if (principal > 0) {
                // Calculate expected yield
                uint256 totalAssets = vault.totalAssets();
                uint256 totalPrincipal = escrow.totalPrincipal();
                uint256 expectedYield = 0;
                
                if (totalAssets > totalPrincipal && totalPrincipal > 0) {
                    expectedYield = ((totalAssets - totalPrincipal) * principal) / totalPrincipal;
                }
                
                console.log("Expected yield:", expectedYield);
                console.log("Total needed:", principal + expectedYield);
                
                // Check if we can withdraw
                uint256 sharesForPrincipal = vault.previewWithdraw(principal);
                uint256 sharesForYield = expectedYield > 0 ? vault.previewWithdraw(expectedYield) : 0;
                uint256 totalSharesNeeded = sharesForPrincipal + sharesForYield;
                
                console.log("Shares needed for principal:", sharesForPrincipal);
                console.log("Shares needed for yield:", sharesForYield);
                console.log("Total shares needed:", totalSharesNeeded);
                console.log("Escrow has shares:", escrowVaultShares);
                
                if (totalSharesNeeded > escrowVaultShares) {
                    console.log("\n!!! ERROR: Not enough shares for withdrawal !!!");
                    console.log("Shortfall:", totalSharesNeeded - escrowVaultShares);
                } else {
                    console.log("\nSufficient shares available for withdrawal");
                }
                
                // Check maxWithdraw after principal withdrawal
                uint256 sharesRemaining = escrowVaultShares - sharesForPrincipal;
                uint256 assetsFromRemainingShares = vault.convertToAssets(sharesRemaining);
                console.log("Assets from remaining shares (after principal):", assetsFromRemainingShares);
                
                if (expectedYield > 0 && assetsFromRemainingShares < expectedYield) {
                    console.log("\n!!! WARNING: May not have enough for yield after principal withdrawal !!!");
                }
            }
        }
    }
}

