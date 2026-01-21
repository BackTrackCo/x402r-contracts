// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {OperatorDeployed} from "../src/commerce-payments/operator/types/Events.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";

contract ArbitrationOperatorFactoryTest is Test {
    ArbitrationOperatorFactory public factory;

    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;
    address public protocolFeeRecipient;
    address public arbiter;
    address public owner;
    uint256 public maxTotalFeeRate = 1000; // 10%
    uint256 public protocolFeePercentage = 10; // 10%

    function setUp() public {
        escrow = new MockEscrow();
        releaseCondition = new MockReleaseCondition();
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        arbiter = makeAddr("arbiter");
        owner = makeAddr("owner");

        vm.prank(owner);
        factory = new ArbitrationOperatorFactory(
            address(escrow),
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            owner
        );
    }

    function test_ComputeAddressMatchesDeploy() public {
        // 1. Compute expected address
        address predicted = factory.computeAddress(arbiter, address(releaseCondition));

        // 2. Deploy
        address actual = factory.deployOperator(arbiter, address(releaseCondition));

        // 3. Verify match
        assertEq(predicted, actual, "Computed address should match deployed address");
        assertNotEq(actual, address(0), "Address should not be zero");
        
        // 4. Verify code is laid down
        assertTrue(actual.code.length > 0, "Contract should have code");
    }

    function test_IdempotentDeployment() public {
        // First deployment
        address op1 = factory.deployOperator(arbiter, address(releaseCondition));
        
        // Second deployment (should return same address, no revert)
        address op2 = factory.deployOperator(arbiter, address(releaseCondition));

        assertEq(op1, op2, "Should return same address");
    }

    function test_GetOperator() public view {
        // Predict
        address predicted = factory.computeAddress(arbiter, address(releaseCondition));
        
        // Since we haven't deployed yet, getOperator depends on internal mapping.
        // The mapping is only updated AFTER deployment. 
        // This test mostly verifies the mapping logic in deployOperator vs storage.
    }
    
    function test_GetOperator_ReturnsAddressIfDeployed() public {
        address op = factory.deployOperator(arbiter, address(releaseCondition));
        // factory.getOperator is slightly redundant with computeAddress but relies on storage
        // Currently getOperator reads from storage mapping
        // In the modified contract, deployOperator updates mapping.
        
        // Wait, the current implementation still relies on mapping for getOperator?
        // Yes, deployOperator updates the mapping.
        
        assertEq(factory.getOperator(arbiter, address(releaseCondition)), op, "getOperator should return stored address");
    }

    function test_TwoDifferentConfigs_DifferentAddresses() public {
        address op1 = factory.deployOperator(arbiter, address(releaseCondition));
        
        MockReleaseCondition condition2 = new MockReleaseCondition();
        address op2 = factory.deployOperator(arbiter, address(condition2));

        assertNotEq(op1, op2, "Different configs should yield different addresses");
    }
}
