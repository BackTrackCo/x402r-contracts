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
            address(escrow), protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, owner
        );
    }

    function _createConfig(address _arbiter, address _releaseCondition)
        internal
        pure
        returns (ArbitrationOperatorFactory.OperatorConfig memory)
    {
        return ArbitrationOperatorFactory.OperatorConfig({
            arbiter: _arbiter,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: _releaseCondition,
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
    }

    function _createSimpleConfig(address _arbiter)
        internal
        pure
        returns (ArbitrationOperatorFactory.OperatorConfig memory)
    {
        return _createConfig(_arbiter, address(0));
    }

    function test_ComputeAddressMatchesDeploy() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = _createConfig(arbiter, address(releaseCondition));

        // 1. Compute expected address
        address predicted = factory.computeAddress(config);

        // 2. Deploy
        address actual = factory.deployOperator(config);

        // 3. Verify match
        assertEq(predicted, actual, "Computed address should match deployed address");
        assertNotEq(actual, address(0), "Address should not be zero");

        // 4. Verify code is laid down
        assertTrue(actual.code.length > 0, "Contract should have code");
    }

    function test_IdempotentDeployment() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = _createConfig(arbiter, address(releaseCondition));

        // First deployment
        address op1 = factory.deployOperator(config);

        // Second deployment (should return same address, no revert)
        address op2 = factory.deployOperator(config);

        assertEq(op1, op2, "Should return same address");
    }

    function test_GetOperator_ReturnsAddressIfDeployed() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = _createConfig(arbiter, address(releaseCondition));

        address op = factory.deployOperator(config);

        assertEq(factory.getOperator(config), op, "getOperator should return stored address");
    }

    function test_TwoDifferentConfigs_DifferentAddresses() public {
        ArbitrationOperatorFactory.OperatorConfig memory config1 = _createConfig(arbiter, address(releaseCondition));

        address op1 = factory.deployOperator(config1);

        MockReleaseCondition condition2 = new MockReleaseCondition();
        ArbitrationOperatorFactory.OperatorConfig memory config2 = _createConfig(arbiter, address(condition2));

        address op2 = factory.deployOperator(config2);

        assertNotEq(op1, op2, "Different configs should yield different addresses");
    }

    function test_DeployOperatorWithAllZeroConditions() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = _createSimpleConfig(arbiter);
        address op = factory.deployOperator(config);
        ArbitrationOperator deployedOp = ArbitrationOperator(op);

        // Verify all conditions are zero
        assertEq(address(deployedOp.AUTHORIZE_CONDITION()), address(0));
        assertEq(address(deployedOp.RELEASE_CONDITION()), address(0));
        assertEq(address(deployedOp.REFUND_IN_ESCROW_CONDITION()), address(0));
        assertEq(address(deployedOp.REFUND_POST_ESCROW_CONDITION()), address(0));
    }

    function test_DeployOperatorWithZeroConditions_Idempotent() public {
        ArbitrationOperatorFactory.OperatorConfig memory config = _createSimpleConfig(arbiter);
        address op1 = factory.deployOperator(config);
        address op2 = factory.deployOperator(config);

        assertEq(op1, op2, "Should return same address");
    }
}
