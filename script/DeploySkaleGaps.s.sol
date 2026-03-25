// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";

/// @notice Minimal interface for CreateX's CREATE3 deployment
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/**
 * @title DeploySkaleGaps
 * @notice Deploy the missing CREATE3 contracts on SKALE Base using the exact
 *         salts from DeployCreate3.s.sol (kebab-case labels).
 *
 * @dev SKALE Base uses Shanghai EVM — no tload/tstore support.
 *      Contracts are deployed with nonTransientReentrancyGuardMode = true.
 *
 * Usage:
 *   source .env && \
 *   forge script script/DeploySkaleGaps.s.sol --rpc-url skale-base --broadcast --legacy --slow --private-key $PRIVATE_KEY -vvvv
 */
contract DeploySkaleGaps is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Already-deployed CREATE3 addresses on SKALE
    address constant ESCROW = 0xe050bB89eD43BB02d71343063824614A7fb80B77;
    address constant PROTOCOL_FEE_CONFIG = 0x7e868A42a458fa2443b6259419aA6A8a161E08c8;

    // SKALE is Shanghai EVM — no tload/tstore
    bool constant NON_TRANSIENT = true;

    function run() external {
        console.log("\n========================================");
        console.log("  SKALE Base Gap Deployment (CREATE3)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        // 1. PaymentOperatorFactory — label "payment-operator-factory" (matches DeployCreate3)
        address paymentOperatorFactory = _deploy3(
            "payment-operator-factory",
            abi.encodePacked(
                type(PaymentOperatorFactory).creationCode, abi.encode(ESCROW, PROTOCOL_FEE_CONFIG, NON_TRANSIENT)
            )
        );
        console.log("PaymentOperatorFactory:", paymentOperatorFactory);

        // 2. RefundRequestFactory — label "sig-refund-request-factory" (matches DeployCreate3)
        address refundReqFactory = _deploy3(
            "sig-refund-request-factory",
            abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(NON_TRANSIENT))
        );
        console.log("RefundRequestFactory:", refundReqFactory);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("PaymentOperatorFactory:", paymentOperatorFactory);
        console.log("RefundRequestFactory:", refundReqFactory);
        console.log("========================================");
    }

    function _deploy3(string memory _label, bytes memory initCode) internal returns (address) {
        bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(_label)))));
        return CREATEX.deployCreate3(salt, initCode);
    }
}
