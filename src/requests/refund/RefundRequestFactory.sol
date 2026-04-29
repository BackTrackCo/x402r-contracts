// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {RefundRequest} from "./RefundRequest.sol";
import {ZeroAddress} from "../../types/Errors.sol";

/**
 * @title RefundRequestFactory
 * @notice Factory for deploying RefundRequest instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(arbiter). Each unique arbiter gets one canonical deployment.
 *      ESCROW is factory-level (immutable), shared across every RefundRequest deployed
 *      by this factory.
 */
contract RefundRequestFactory {
    error ZeroArbiter();

    /// @notice Salt prefix for CREATE2
    bytes32 private constant SALT_PREFIX = "refundRequest";

    /// @notice Canonical escrow injected into every deployed RefundRequest
    AuthCaptureEscrow public immutable ESCROW;

    /// @notice Deployed refund request addresses
    /// @dev Key: keccak256(abi.encode(arbiter))
    mapping(bytes32 => address) public refundRequests;

    /// @notice Emitted when a new refund request is deployed
    event RefundRequestDeployed(address indexed refundRequest, address indexed arbiter);

    constructor(address escrow) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
    }

    /**
     * @notice Deploy a new RefundRequest for an arbiter
     * @param arbiter The arbiter address to bind to
     * @return refundRequest Address of the deployed refund request
     */
    function deploy(address arbiter) external returns (address refundRequest) {
        if (arbiter == address(0)) revert ZeroArbiter();

        bytes32 key = getKey(arbiter);

        // Return existing deployment if already deployed
        if (refundRequests[key] != address(0)) {
            return refundRequests[key];
        }

        // ============ EFFECTS ============
        bytes32 salt = keccak256(abi.encode(SALT_PREFIX, key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequest).creationCode, abi.encode(arbiter, address(ESCROW)));
        refundRequest = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        refundRequests[key] = refundRequest;

        // ============ INTERACTIONS ============
        address deployed = address(new RefundRequest{salt: salt}(arbiter, address(ESCROW)));

        assert(deployed == refundRequest);

        // Emit event AFTER deploy
        emit RefundRequestDeployed(refundRequest, arbiter);
    }

    /**
     * @notice Get deployed address for an arbiter
     * @param arbiter The arbiter address
     * @return refundRequest Address (address(0) if not deployed)
     */
    function getDeployed(address arbiter) external view returns (address refundRequest) {
        return refundRequests[getKey(arbiter)];
    }

    /**
     * @notice Compute the deterministic address for an arbiter (before deployment)
     * @param arbiter The arbiter address
     * @return refundRequest Predicted address
     */
    function computeAddress(address arbiter) external view returns (address refundRequest) {
        bytes32 key = getKey(arbiter);
        bytes32 salt = keccak256(abi.encode(SALT_PREFIX, key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequest).creationCode, abi.encode(arbiter, address(ESCROW)));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        refundRequest = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for an arbiter address
     * @param arbiter The arbiter to compute key for
     * @return The mapping key
     */
    function getKey(address arbiter) public pure returns (bytes32) {
        return keccak256(abi.encode(arbiter));
    }
}
