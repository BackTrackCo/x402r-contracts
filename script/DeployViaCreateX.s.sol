// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";

interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/**
 * @title DeployViaCreateX
 * @notice Deploys contracts via CreateX for cross-chain deterministic addresses.
 * @dev CreateX is at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed on all chains.
 *
 *      Set CONTRACT env var to choose which contract to deploy:
 *        CONTRACT=RefundRequestFactory
 *        CONTRACT=RefundRequestEvidenceFactory
 *        CONTRACT=PaymentOperatorFactory
 *
 *      Usage:
 *      CONTRACT=RefundRequestFactory forge script script/DeployViaCreateX.s.sol:DeployViaCreateX \
 *        --rpc-url <RPC> --broadcast --private-key <KEY>
 */
contract DeployViaCreateX is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Unified protocol addresses (constructor args for PaymentOperatorFactory)
    address constant ESCROW = 0xe050bB89eD43BB02d71343063824614A7fb80B77;
    address constant PROTOCOL_FEE_CONFIG = 0x7e868A42a458fa2443b6259419aA6A8a161E08c8;

    function run() public {
        string memory contractName = vm.envString("CONTRACT");
        address deployer = msg.sender;

        bytes memory initCode;
        bytes11 customSalt;

        if (_eq(contractName, "RefundRequestFactory")) {
            initCode = type(RefundRequestFactory).creationCode;
            customSalt = bytes11(keccak256("x402r.RefundRequestFactory.v1"));
        } else if (_eq(contractName, "RefundRequestEvidenceFactory")) {
            initCode = type(RefundRequestEvidenceFactory).creationCode;
            customSalt = bytes11(keccak256("x402r.RefundRequestEvidenceFactory.v1"));
        } else if (_eq(contractName, "PaymentOperatorFactory")) {
            initCode = abi.encodePacked(
                type(PaymentOperatorFactory).creationCode, abi.encode(ESCROW, PROTOCOL_FEE_CONFIG)
            );
            customSalt = bytes11(keccak256("x402r.PaymentOperatorFactory.v2"));
        } else {
            revert(string.concat("Unknown contract: ", contractName));
        }

        bytes32 salt = bytes32(abi.encodePacked(deployer, bytes1(0x00), customSalt));

        console.log("=== DeployViaCreateX ===");
        console.log("Contract:", contractName);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);

        vm.startBroadcast();

        address deployed = CREATEX.deployCreate3(salt, initCode);
        console.log("Deployed at:", deployed);

        vm.stopBroadcast();
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
