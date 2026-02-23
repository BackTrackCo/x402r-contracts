// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {SignatureRefundRequest} from "./SignatureRefundRequest.sol";

/**
 * @title SignatureRefundRequestFactory
 * @notice Factory for deploying SignatureRefundRequest instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(signatureCondition). Each unique SignatureCondition gets one canonical deployment.
 */
contract SignatureRefundRequestFactory {
    error ZeroCondition();

    /// @notice Deployed refund request addresses
    /// @dev Key: keccak256(abi.encodePacked(signatureCondition))
    mapping(bytes32 => address) public refundRequests;

    /// @notice Emitted when a new refund request is deployed
    event SignatureRefundRequestDeployed(address indexed refundRequest, address indexed signatureCondition);

    /**
     * @notice Deploy a new SignatureRefundRequest for a SignatureCondition
     * @param signatureCondition The SignatureCondition address to bind to
     * @return refundRequest Address of the deployed refund request
     */
    function deploy(address signatureCondition) external returns (address refundRequest) {
        if (signatureCondition == address(0)) revert ZeroCondition();

        bytes32 key = getKey(signatureCondition);

        // Return existing deployment if already deployed
        if (refundRequests[key] != address(0)) {
            return refundRequests[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("signatureRefundRequest", key));
        bytes memory bytecode =
            abi.encodePacked(type(SignatureRefundRequest).creationCode, abi.encode(signatureCondition));
        refundRequest = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        refundRequests[key] = refundRequest;

        emit SignatureRefundRequestDeployed(refundRequest, signatureCondition);

        // ============ INTERACTIONS ============
        address deployed = address(new SignatureRefundRequest{salt: salt}(signatureCondition));

        assert(deployed == refundRequest);
    }

    /**
     * @notice Get deployed address for a SignatureCondition
     * @param signatureCondition The SignatureCondition address
     * @return refundRequest Address (address(0) if not deployed)
     */
    function getDeployed(address signatureCondition) external view returns (address refundRequest) {
        return refundRequests[getKey(signatureCondition)];
    }

    /**
     * @notice Compute the deterministic address for a SignatureCondition (before deployment)
     * @param signatureCondition The SignatureCondition address
     * @return refundRequest Predicted address
     */
    function computeAddress(address signatureCondition) external view returns (address refundRequest) {
        bytes32 key = getKey(signatureCondition);
        bytes32 salt = keccak256(abi.encodePacked("signatureRefundRequest", key));
        bytes memory bytecode =
            abi.encodePacked(type(SignatureRefundRequest).creationCode, abi.encode(signatureCondition));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        refundRequest = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a SignatureCondition address
     * @param signatureCondition The condition to compute key for
     * @return The mapping key
     */
    function getKey(address signatureCondition) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(signatureCondition));
    }
}
