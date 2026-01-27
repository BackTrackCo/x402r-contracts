// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {StaticFeeCalculator} from "./StaticFeeCalculator.sol";

/**
 * @title StaticFeeCalculatorFactory
 * @notice Factory for deploying StaticFeeCalculator instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(feeBps). Each unique fee rate gets one canonical deployment.
 */
contract StaticFeeCalculatorFactory {
    /// @notice Deployed calculator addresses
    /// @dev Key: keccak256(abi.encodePacked(feeBps))
    mapping(bytes32 => address) public calculators;

    /// @notice Emitted when a new calculator is deployed
    event StaticFeeCalculatorDeployed(address indexed calculator, uint256 feeBps);

    /**
     * @notice Deploy a new StaticFeeCalculator
     * @param feeBps Fee in basis points
     * @return calculator Address of the deployed calculator
     */
    function deploy(uint256 feeBps) external returns (address calculator) {
        bytes32 key = getKey(feeBps);

        // Return existing deployment if already deployed
        if (calculators[key] != address(0)) {
            return calculators[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("staticFeeCalculator", key));
        bytes memory bytecode = abi.encodePacked(type(StaticFeeCalculator).creationCode, abi.encode(feeBps));
        calculator = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        calculators[key] = calculator;

        emit StaticFeeCalculatorDeployed(calculator, feeBps);

        // ============ INTERACTIONS ============
        address deployed = address(new StaticFeeCalculator{salt: salt}(feeBps));

        assert(deployed == calculator);
    }

    /**
     * @notice Get deployed address for a fee rate
     * @param feeBps Fee in basis points
     * @return calculator Address (address(0) if not deployed)
     */
    function getDeployed(uint256 feeBps) external view returns (address calculator) {
        return calculators[getKey(feeBps)];
    }

    /**
     * @notice Compute the deterministic address for a fee rate (before deployment)
     * @param feeBps Fee in basis points
     * @return calculator Predicted address
     */
    function computeAddress(uint256 feeBps) external view returns (address calculator) {
        bytes32 key = getKey(feeBps);
        bytes32 salt = keccak256(abi.encodePacked("staticFeeCalculator", key));
        bytes memory bytecode = abi.encodePacked(type(StaticFeeCalculator).creationCode, abi.encode(feeBps));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        calculator = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a fee rate
     * @param feeBps Fee in basis points
     * @return The mapping key
     */
    function getKey(uint256 feeBps) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(feeBps));
    }
}
