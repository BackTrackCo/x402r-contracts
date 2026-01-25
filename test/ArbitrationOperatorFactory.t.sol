// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {PayerOnly} from "../src/commerce-payments/release-conditions/defaults/PayerOnly.sol";
import {ReceiverOrArbiter} from "../src/commerce-payments/release-conditions/defaults/ReceiverOrArbiter.sol";
import {OperatorDeployed} from "../src/commerce-payments/operator/types/Events.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {MockReleaseCondition} from "./mocks/MockReleaseCondition.sol";

contract ArbitrationOperatorFactoryTest is Test {
    ArbitrationOperatorFactory public factory;

    MockEscrow public escrow;
    MockReleaseCondition public releaseCondition;
    PayerOnly public payerOnly;
    ReceiverOrArbiter public receiverOrArbiter;
    address public protocolFeeRecipient;
    address public arbiter;
    address public owner;
    uint256 public maxTotalFeeRate = 1000; // 10%
    uint256 public protocolFeePercentage = 10; // 10%

    function setUp() public {
        escrow = new MockEscrow();
        releaseCondition = new MockReleaseCondition();
        payerOnly = new PayerOnly();
        receiverOrArbiter = new ReceiverOrArbiter();
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
        address predicted = factory.computeAddress(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        // 2. Deploy
        address actual = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        // 3. Verify match
        assertEq(predicted, actual, "Computed address should match deployed address");
        assertNotEq(actual, address(0), "Address should not be zero");

        // 4. Verify code is laid down
        assertTrue(actual.code.length > 0, "Contract should have code");
    }

    function test_IdempotentDeployment() public {
        // First deployment
        address op1 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        // Second deployment (should return same address, no revert)
        address op2 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        assertEq(op1, op2, "Should return same address");
    }

    function test_GetOperator_ReturnsAddressIfDeployed() public {
        address op = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        assertEq(
            factory.getOperator(
                arbiter,
                address(0), address(0),
                address(releaseCondition), address(0),
                address(receiverOrArbiter), address(0),
                address(0), address(0)
            ),
            op,
            "getOperator should return stored address"
        );
    }

    function test_TwoDifferentConfigs_DifferentAddresses() public {
        address op1 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(releaseCondition), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        MockReleaseCondition condition2 = new MockReleaseCondition();
        address op2 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(condition2), address(0),
            address(receiverOrArbiter), address(0),
            address(0), address(0)
        );

        assertNotEq(op1, op2, "Different configs should yield different addresses");
    }

    function test_DeployOperator_AllZeroConditions() public {
        address op = factory.deployOperator(
            arbiter,
            address(0), address(0),  // CAN_AUTHORIZE, NOTE_AUTHORIZE
            address(0), address(0),  // CAN_RELEASE, NOTE_RELEASE  
            address(0), address(0),  // CAN_REFUND_IN_ESCROW, NOTE_REFUND_IN_ESCROW
            address(0), address(0)   // CAN_REFUND_POST_ESCROW, NOTE_REFUND_POST_ESCROW
        );
        ArbitrationOperator operator = ArbitrationOperator(op);

        // Verify all conditions are zero
        assertEq(address(operator.CAN_AUTHORIZE()), address(0));
        assertEq(address(operator.NOTE_AUTHORIZE()), address(0));
        assertEq(address(operator.CAN_RELEASE()), address(0));
        assertEq(address(operator.NOTE_RELEASE()), address(0));
        assertEq(address(operator.CAN_REFUND_IN_ESCROW()), address(0));
        assertEq(address(operator.NOTE_REFUND_IN_ESCROW()), address(0));
        assertEq(address(operator.CAN_REFUND_POST_ESCROW()), address(0));
        assertEq(address(operator.NOTE_REFUND_POST_ESCROW()), address(0));
    }

    function test_DeployOperator_Idempotent() public {
        address op1 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(0), address(0),
            address(0), address(0),
            address(0), address(0)
        );
        address op2 = factory.deployOperator(
            arbiter,
            address(0), address(0),
            address(0), address(0),
            address(0), address(0),
            address(0), address(0)
        );

        assertEq(op1, op2, "Should return same address");
    }
}
