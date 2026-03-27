// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestEvidenceFactory} from "../../src/evidence/RefundRequestEvidenceFactory.sol";

interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
}

contract DeployRefundRequestEvidenceFactory is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");

        vm.startBroadcast(deployerPk);

        address deployed = _deploy3(label, abi.encodePacked(type(RefundRequestEvidenceFactory).creationCode));
        console.log("RefundRequestEvidenceFactory:", deployed);

        vm.stopBroadcast();
    }

    function _deploy3(string memory _label, bytes memory initCode) internal returns (address) {
        bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(_label)))));
        return CREATEX.deployCreate3(salt, initCode);
    }
}
