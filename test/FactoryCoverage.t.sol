// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {Freeze} from "../src/plugins/freeze/Freeze.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {ICondition} from "../src/plugins/conditions/ICondition.sol";
import {AndCondition} from "../src/plugins/conditions/combinators/AndCondition.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {NotCondition} from "../src/plugins/conditions/combinators/NotCondition.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {OrCondition} from "../src/plugins/conditions/combinators/OrCondition.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {IRecorder} from "../src/plugins/recorders/IRecorder.sol";
import {AuthorizationTimeRecorder} from "../src/plugins/recorders/AuthorizationTimeRecorder.sol";
import {RecorderCombinator} from "../src/plugins/recorders/combinators/RecorderCombinator.sol";
import {RecorderCombinatorFactory} from "../src/plugins/recorders/combinators/RecorderCombinatorFactory.sol";

/**
 * @title FactoryCoverageTest
 * @notice Tests for factory contracts: idempotent deployments, computeAddress, edge cases
 */
contract FactoryCoverageTest is Test {
    AuthCaptureEscrow public escrow;
    ProtocolFeeConfig public protocolFeeConfig;

    address public owner;
    address public protocolFeeRecipient;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        escrow = new AuthCaptureEscrow();
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
    }

    // ============ StaticFeeCalculatorFactory ============

    function test_StaticFeeCalculatorFactory_Deploy() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address calc = factory.deploy(100); // 1%
        assertTrue(calc != address(0), "Calculator should be deployed");
        assertEq(StaticFeeCalculator(calc).FEE_BPS(), 100, "Fee BPS should match");
    }

    function test_StaticFeeCalculatorFactory_IdempotentDeploy() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address first = factory.deploy(100);
        address second = factory.deploy(100);
        assertEq(first, second, "Same config should return same address");
    }

    function test_StaticFeeCalculatorFactory_DifferentBpsGetDifferentAddresses() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address calc100 = factory.deploy(100);
        address calc200 = factory.deploy(200);
        assertTrue(calc100 != calc200, "Different BPS should produce different addresses");
    }

    function test_StaticFeeCalculatorFactory_ComputeAddress() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address predicted = factory.computeAddress(100);
        address actual = factory.deploy(100);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_StaticFeeCalculatorFactory_GetDeployed() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        assertEq(factory.getDeployed(100), address(0), "Should be zero before deployment");
        address calc = factory.deploy(100);
        assertEq(factory.getDeployed(100), calc, "Should return deployed address");
    }

    function test_StaticFeeCalculatorFactory_ZeroBps() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address calc = factory.deploy(0);
        assertEq(StaticFeeCalculator(calc).FEE_BPS(), 0, "Zero BPS should work");
    }

    function test_StaticFeeCalculatorFactory_MaxBps() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        address calc = factory.deploy(10000);
        assertEq(StaticFeeCalculator(calc).FEE_BPS(), 10000, "Max BPS should work");
    }

    function test_StaticFeeCalculatorFactory_OverMaxBps_Reverts() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        vm.expectRevert(StaticFeeCalculatorFactory.FeeTooHigh.selector);
        factory.deploy(10001);
    }

    function test_StaticFeeCalculatorFactory_GetKey() public {
        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        bytes32 key1 = factory.getKey(100);
        bytes32 key2 = factory.getKey(200);
        assertTrue(key1 != key2, "Different BPS should produce different keys");
        assertEq(key1, factory.getKey(100), "Same BPS should produce same key");
    }

    // ============ EscrowPeriodFactory ============

    function test_EscrowPeriodFactory_Deploy() public {
        EscrowPeriodFactory factory = new EscrowPeriodFactory(address(escrow));

        address escrowPeriodAddr = factory.deploy(7 days, bytes32(0));
        assertTrue(escrowPeriodAddr != address(0), "EscrowPeriod should be deployed");
    }

    function test_EscrowPeriodFactory_IdempotentDeploy() public {
        EscrowPeriodFactory factory = new EscrowPeriodFactory(address(escrow));

        address first = factory.deploy(7 days, bytes32(0));
        address second = factory.deploy(7 days, bytes32(0));
        assertEq(first, second, "Same config should return same address");
    }

    function test_EscrowPeriodFactory_GetDeployed() public {
        EscrowPeriodFactory factory = new EscrowPeriodFactory(address(escrow));

        address before = factory.getDeployed(7 days, bytes32(0));
        assertEq(before, address(0), "Should be zero before deployment");

        address deployed = factory.deploy(7 days, bytes32(0));

        address after_ = factory.getDeployed(7 days, bytes32(0));
        assertEq(after_, deployed, "Should return deployed address");
    }

    function test_EscrowPeriodFactory_ComputeAddress() public {
        EscrowPeriodFactory factory = new EscrowPeriodFactory(address(escrow));

        address predicted = factory.computeAddress(7 days, bytes32(0));
        address actual = factory.deploy(7 days, bytes32(0));

        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_EscrowPeriodFactory_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new EscrowPeriodFactory(address(0));
    }

    function test_EscrowPeriodFactory_GetKey() public {
        EscrowPeriodFactory factory = new EscrowPeriodFactory(address(escrow));
        bytes32 key1 = factory.getKey(7 days, bytes32(0));
        bytes32 key2 = factory.getKey(14 days, bytes32(0));
        assertTrue(key1 != key2, "Different configs should produce different keys");
    }

    // ============ FreezeFactory ============

    function test_FreezeFactory_Deploy() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertTrue(freezeAddr != address(0), "Freeze should be deployed");
    }

    function test_FreezeFactory_IdempotentDeploy() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        address first = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        address second = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertEq(first, second, "Same config should return same address");
    }

    function test_FreezeFactory_GetDeployed() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        assertEq(
            factory.getDeployed(address(payerCond), address(payerCond), 3 days, address(0)),
            address(0),
            "Should be zero before deployment"
        );

        address deployed = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertEq(
            factory.getDeployed(address(payerCond), address(payerCond), 3 days, address(0)),
            deployed,
            "Should return deployed address"
        );
    }

    function test_FreezeFactory_ComputeAddress() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        address predicted = factory.computeAddress(address(payerCond), address(payerCond), 3 days, address(0));
        address actual = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_FreezeFactory_WithEscrowPeriod() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        EscrowPeriodFactory epFactory = new EscrowPeriodFactory(address(escrow));
        address ep = epFactory.deploy(7 days, bytes32(0));

        PayerCondition payerCond = new PayerCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, ep);
        assertTrue(freezeAddr != address(0), "Freeze with escrow period should be deployed");

        Freeze freezeContract = Freeze(freezeAddr);
        assertEq(address(freezeContract.ESCROW_PERIOD_CONTRACT()), ep, "Escrow period should match");
    }

    function test_FreezeFactory_DifferentConfigs() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        address f1 = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        address f2 = factory.deploy(address(payerCond), address(payerCond), 7 days, address(0));
        assertTrue(f1 != f2, "Different durations should produce different addresses");
    }

    function test_FreezeFactory_DifferentConditions() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        ReceiverCondition receiverCond = new ReceiverCondition();

        address f1 = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        address f2 = factory.deploy(address(payerCond), address(receiverCond), 3 days, address(0));
        assertTrue(f1 != f2, "Different conditions should produce different addresses");
    }

    function test_FreezeFactory_GetKey() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        bytes32 key1 = factory.getKey(address(1), address(1), 3 days, address(0));
        bytes32 key2 = factory.getKey(address(2), address(2), 3 days, address(0));
        assertTrue(key1 != key2, "Different configs should produce different keys");
    }

    function test_FreezeFactory_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new FreezeFactory(address(0));
    }

    function test_FreezeFactory_ZeroDuration() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 0, address(0));
        assertEq(Freeze(freezeAddr).FREEZE_DURATION(), 0, "Zero duration means permanent freeze");
    }

    function test_FreezeFactory_DeployedFreezeWorks() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        Freeze freezeContract = Freeze(freezeAddr);

        assertEq(address(freezeContract.FREEZE_CONDITION()), address(payerCond));
        assertEq(address(freezeContract.UNFREEZE_CONDITION()), address(payerCond));
        assertEq(freezeContract.FREEZE_DURATION(), 3 days);
    }

    // ============ AndConditionFactory ============

    function test_AndConditionFactory_Deploy() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(new PayerCondition()));
        conds[1] = ICondition(address(new ReceiverCondition()));

        address deployed = factory.deploy(conds);
        assertTrue(deployed != address(0), "AndCondition should be deployed");
        assertEq(AndCondition(deployed).conditionCount(), 2, "Should have 2 conditions");
    }

    function test_AndConditionFactory_IdempotentDeploy() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        address first = factory.deploy(conds);
        address second = factory.deploy(conds);
        assertEq(first, second, "Same conditions should return same address");
    }

    function test_AndConditionFactory_ComputeAddress() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        address predicted = factory.computeAddress(conds);
        address actual = factory.deploy(conds);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_AndConditionFactory_GetDeployed() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        assertEq(factory.getDeployed(conds), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(conds);
        assertEq(factory.getDeployed(conds), deployed, "Should return deployed address");
    }

    function test_AndConditionFactory_NoConditions_Reverts() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](0);
        vm.expectRevert(AndConditionFactory.NoConditions.selector);
        factory.deploy(conds);
    }

    function test_AndConditionFactory_TooManyConditions_Reverts() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds = new ICondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conds[i] = ICondition(address(new PayerCondition()));
        }
        vm.expectRevert(AndConditionFactory.TooManyConditions.selector);
        factory.deploy(conds);
    }

    function test_AndConditionFactory_GetKey() public {
        AndConditionFactory factory = new AndConditionFactory();
        ICondition[] memory conds1 = new ICondition[](1);
        conds1[0] = ICondition(address(new PayerCondition()));
        ICondition[] memory conds2 = new ICondition[](1);
        conds2[0] = ICondition(address(new ReceiverCondition()));

        bytes32 key1 = factory.getKey(conds1);
        bytes32 key2 = factory.getKey(conds2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ NotConditionFactory ============

    function test_NotConditionFactory_Deploy() public {
        NotConditionFactory factory = new NotConditionFactory();
        ICondition cond = ICondition(address(new PayerCondition()));

        address deployed = factory.deploy(cond);
        assertTrue(deployed != address(0), "NotCondition should be deployed");
    }

    function test_NotConditionFactory_IdempotentDeploy() public {
        NotConditionFactory factory = new NotConditionFactory();
        ICondition cond = ICondition(address(new PayerCondition()));

        address first = factory.deploy(cond);
        address second = factory.deploy(cond);
        assertEq(first, second, "Same condition should return same address");
    }

    function test_NotConditionFactory_ComputeAddress() public {
        NotConditionFactory factory = new NotConditionFactory();
        ICondition cond = ICondition(address(new PayerCondition()));

        address predicted = factory.computeAddress(cond);
        address actual = factory.deploy(cond);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_NotConditionFactory_GetDeployed() public {
        NotConditionFactory factory = new NotConditionFactory();
        ICondition cond = ICondition(address(new PayerCondition()));

        assertEq(factory.getDeployed(cond), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(cond);
        assertEq(factory.getDeployed(cond), deployed, "Should return deployed address");
    }

    function test_NotConditionFactory_ZeroCondition_Reverts() public {
        NotConditionFactory factory = new NotConditionFactory();
        vm.expectRevert(NotConditionFactory.ZeroCondition.selector);
        factory.deploy(ICondition(address(0)));
    }

    function test_NotConditionFactory_GetKey() public {
        NotConditionFactory factory = new NotConditionFactory();
        ICondition cond1 = ICondition(address(new PayerCondition()));
        ICondition cond2 = ICondition(address(new ReceiverCondition()));

        bytes32 key1 = factory.getKey(cond1);
        bytes32 key2 = factory.getKey(cond2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ OrConditionFactory ============

    function test_OrConditionFactory_Deploy() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(new PayerCondition()));
        conds[1] = ICondition(address(new ReceiverCondition()));

        address deployed = factory.deploy(conds);
        assertTrue(deployed != address(0), "OrCondition should be deployed");
        assertEq(OrCondition(deployed).conditionCount(), 2, "Should have 2 conditions");
    }

    function test_OrConditionFactory_IdempotentDeploy() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        address first = factory.deploy(conds);
        address second = factory.deploy(conds);
        assertEq(first, second, "Same conditions should return same address");
    }

    function test_OrConditionFactory_ComputeAddress() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        address predicted = factory.computeAddress(conds);
        address actual = factory.deploy(conds);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_OrConditionFactory_GetDeployed() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](1);
        conds[0] = ICondition(address(new PayerCondition()));

        assertEq(factory.getDeployed(conds), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(conds);
        assertEq(factory.getDeployed(conds), deployed, "Should return deployed address");
    }

    function test_OrConditionFactory_NoConditions_Reverts() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](0);
        vm.expectRevert(OrConditionFactory.NoConditions.selector);
        factory.deploy(conds);
    }

    function test_OrConditionFactory_TooManyConditions_Reverts() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds = new ICondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conds[i] = ICondition(address(new PayerCondition()));
        }
        vm.expectRevert(OrConditionFactory.TooManyConditions.selector);
        factory.deploy(conds);
    }

    function test_OrConditionFactory_GetKey() public {
        OrConditionFactory factory = new OrConditionFactory();
        ICondition[] memory conds1 = new ICondition[](1);
        conds1[0] = ICondition(address(new PayerCondition()));
        ICondition[] memory conds2 = new ICondition[](1);
        conds2[0] = ICondition(address(new ReceiverCondition()));

        bytes32 key1 = factory.getKey(conds1);
        bytes32 key2 = factory.getKey(conds2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ RecorderCombinatorFactory ============

    function test_RecorderCombinatorFactory_Deploy() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder[] memory recs = new IRecorder[](2);
        recs[0] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        recs[1] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));

        address deployed = factory.deploy(recs);
        assertTrue(deployed != address(0), "RecorderCombinator should be deployed");
        assertEq(RecorderCombinator(deployed).getRecorderCount(), 2, "Should have 2 recorders");
    }

    function test_RecorderCombinatorFactory_IdempotentDeploy() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder rec = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        IRecorder[] memory recs = new IRecorder[](1);
        recs[0] = rec;

        address first = factory.deploy(recs);
        address second = factory.deploy(recs);
        assertEq(first, second, "Same recorders should return same address");
    }

    function test_RecorderCombinatorFactory_ComputeAddress() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder[] memory recs = new IRecorder[](1);
        recs[0] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));

        address predicted = factory.computeAddress(recs);
        address actual = factory.deploy(recs);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_RecorderCombinatorFactory_GetDeployed() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder[] memory recs = new IRecorder[](1);
        recs[0] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));

        assertEq(factory.getDeployed(recs), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(recs);
        assertEq(factory.getDeployed(recs), deployed, "Should return deployed address");
    }

    function test_RecorderCombinatorFactory_EmptyRecorders_Reverts() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder[] memory recs = new IRecorder[](0);
        vm.expectRevert(RecorderCombinatorFactory.EmptyRecorders.selector);
        factory.deploy(recs);
    }

    function test_RecorderCombinatorFactory_TooManyRecorders_Reverts() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder[] memory recs = new IRecorder[](11);
        for (uint256 i = 0; i < 11; i++) {
            recs[i] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        }
        vm.expectRevert(RecorderCombinatorFactory.TooManyRecorders.selector);
        factory.deploy(recs);
    }

    function test_RecorderCombinatorFactory_GetKey() public {
        RecorderCombinatorFactory factory = new RecorderCombinatorFactory();
        IRecorder rec1 = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        IRecorder rec2 = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        IRecorder[] memory recs1 = new IRecorder[](1);
        recs1[0] = rec1;
        IRecorder[] memory recs2 = new IRecorder[](1);
        recs2[0] = rec2;

        bytes32 key1 = factory.getKey(recs1);
        bytes32 key2 = factory.getKey(recs2);
        assertTrue(key1 != key2, "Different recorders should produce different keys");
    }

    // ============ PaymentOperatorFactory ============

    function test_PaymentOperatorFactory_DifferentConfigs() public {
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config1 = _defaultConfig(address(0));
        PaymentOperatorFactory.OperatorConfig memory config2 = _defaultConfig(address(0));
        config2.feeRecipient = makeAddr("otherRecipient");

        address op1 = factory.deployOperator(config1);
        address op2 = factory.deployOperator(config2);
        assertTrue(op1 != op2, "Different configs should produce different operators");
    }

    function test_PaymentOperatorFactory_ImmutableFields() public {
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        assertEq(address(factory.ESCROW()), address(escrow), "ESCROW should be immutable");
        assertEq(address(factory.PROTOCOL_FEE_CONFIG()), address(protocolFeeConfig), "FEE_CONFIG should be immutable");
    }

    // ============ Helpers ============

    function _defaultConfig(address feeCalc) internal view returns (PaymentOperatorFactory.OperatorConfig memory) {
        return PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: feeCalc,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
    }
}
