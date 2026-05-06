// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create2Deployer} from "./deploy/Create2Deployer.sol";

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";
import {Permit2PaymentCollector} from "commerce-payments/collectors/Permit2PaymentCollector.sol";

/**
 * @title DeployCommercePayments
 * @notice Deterministic CREATE2 deployment of the upstream `base/commerce-payments` primitives
 *         at canonical addresses. The deployed contracts here are vendored unchanged from
 *         `base/commerce-payments` (MIT-licensed, pinned to the `v1.0.0` tag in the submodule);
 *         this script is x402r's deploy automation around them (BUSL-1.1, like the rest of
 *         `script/`).
 *
 * @dev Salt namespace: `commerce-payments::v1::<ContractName>`.
 *      Idempotent per chain: re-running on a chain where the addresses already exist will
 *      revert (CreateX rejects duplicate CREATE2 deploys). That's intentional — it's the
 *      first-mover lock. To deploy on a new chain, just run this script.
 *
 *      Pre-flight (per chain):
 *      - CreateX live at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
 *      - Multicall3 live at 0xcA11bde05977b3631167028862bE2a173976CA11 (used by ERC3009 collector)
 *      - Permit2 live at 0x000000000022D473030F116dDEE9F6B43aC78BA3 (used by Permit2 collector)
 *
 *      Reproducibility (see foundry.toml + lib/commerce-payments at v1.0.0):
 *      - solc version locked
 *      - evm_version = cancun (matches upstream commerce-payments deploy profile)
 *      - optimizer_runs = 100000
 *      - bytecode_hash = none
 *
 *      Usage:
 *        forge script script/DeployCommercePayments.s.sol --rpc-url <RPC> --broadcast --verify -vvv
 */
contract DeployCommercePayments is Create2Deployer {
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("  base/commerce-payments primitives (CREATE2)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPk));

        vm.startBroadcast(deployerPk);

        address escrow = _deploy2("commerce-payments::v1::AuthCaptureEscrow", type(AuthCaptureEscrow).creationCode);
        console.log("AuthCaptureEscrow:", escrow);

        address erc3009Collector = _deploy2(
            "commerce-payments::v1::ERC3009PaymentCollector",
            abi.encodePacked(type(ERC3009PaymentCollector).creationCode, abi.encode(escrow, MULTICALL3))
        );
        console.log("ERC3009PaymentCollector:", erc3009Collector);

        address permit2Collector = _deploy2(
            "commerce-payments::v1::Permit2PaymentCollector",
            abi.encodePacked(type(Permit2PaymentCollector).creationCode, abi.encode(escrow, PERMIT2, MULTICALL3))
        );
        console.log("Permit2PaymentCollector:", permit2Collector);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  PRIMITIVES DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("  AuthCaptureEscrow:       ", escrow);
        console.log("  ERC3009PaymentCollector: ", erc3009Collector);
        console.log("  Permit2PaymentCollector: ", permit2Collector);
        console.log("========================================");
    }
}
