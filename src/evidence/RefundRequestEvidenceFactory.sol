// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RefundRequestEvidence} from "./RefundRequestEvidence.sol";

/**
 * @title RefundRequestEvidenceFactory
 * @notice Factory for deploying RefundRequestEvidence instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(refundRequest). Each unique RefundRequest gets one canonical deployment.
 */
contract RefundRequestEvidenceFactory {
    error ZeroRefundRequest();

    /// @notice Salt prefix for CREATE2
    bytes32 private constant SALT_PREFIX = "refundRequestEvidence";

    /// @notice Deployed evidence contract addresses
    /// @dev Key: keccak256(abi.encodePacked(refundRequest))
    mapping(bytes32 => address) public evidenceContracts;

    /// @notice Emitted when a new evidence contract is deployed
    event RefundRequestEvidenceDeployed(address indexed evidence, address indexed refundRequest);

    /**
     * @notice Deploy a new RefundRequestEvidence for a RefundRequest
     * @param refundRequest The RefundRequest address to bind to
     * @return evidence Address of the deployed evidence contract
     */
    function deploy(address refundRequest) external returns (address evidence) {
        if (refundRequest == address(0)) revert ZeroRefundRequest();

        bytes32 key = getKey(refundRequest);

        // Return existing deployment if already deployed
        if (evidenceContracts[key] != address(0)) {
            return evidenceContracts[key];
        }

        // ============ EFFECTS ============
        bytes32 salt = keccak256(abi.encodePacked(SALT_PREFIX, key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequestEvidence).creationCode, abi.encode(refundRequest));
        evidence = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        evidenceContracts[key] = evidence;

        // ============ INTERACTIONS ============
        address deployed = address(new RefundRequestEvidence{salt: salt}(refundRequest));

        assert(deployed == evidence);

        // Emit event AFTER deploy
        emit RefundRequestEvidenceDeployed(evidence, refundRequest);
    }

    /**
     * @notice Get deployed address for a RefundRequest
     * @param refundRequest The RefundRequest address
     * @return evidence Address (address(0) if not deployed)
     */
    function getDeployed(address refundRequest) external view returns (address evidence) {
        return evidenceContracts[getKey(refundRequest)];
    }

    /**
     * @notice Compute the deterministic address for a RefundRequest (before deployment)
     * @param refundRequest The RefundRequest address
     * @return evidence Predicted address
     */
    function computeAddress(address refundRequest) external view returns (address evidence) {
        bytes32 key = getKey(refundRequest);
        bytes32 salt = keccak256(abi.encodePacked(SALT_PREFIX, key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequestEvidence).creationCode, abi.encode(refundRequest));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        evidence = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a RefundRequest address
     * @param refundRequest The RefundRequest to compute key for
     * @return The mapping key
     */
    function getKey(address refundRequest) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(refundRequest));
    }
}
