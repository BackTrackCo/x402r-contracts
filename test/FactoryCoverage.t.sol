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
import {PayerPreActionCondition} from "../src/plugins/pre-action-conditions/access/PayerPreActionCondition.sol";
import {ReceiverPreActionCondition} from "../src/plugins/pre-action-conditions/access/ReceiverPreActionCondition.sol";
import {IPreActionCondition} from "../src/plugins/pre-action-conditions/IPreActionCondition.sol";
import {AndPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/AndPreActionCondition.sol";
import {
    AndPreActionConditionFactory
} from "../src/plugins/pre-action-conditions/combinators/AndPreActionConditionFactory.sol";
import {
    NotPreActionConditionFactory
} from "../src/plugins/pre-action-conditions/combinators/NotPreActionConditionFactory.sol";
import {OrPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/OrPreActionCondition.sol";
import {
    OrPreActionConditionFactory
} from "../src/plugins/pre-action-conditions/combinators/OrPreActionConditionFactory.sol";
import {IPostActionHook} from "../src/plugins/post-action-hooks/IPostActionHook.sol";
import {AuthorizationTimePostActionHook} from "../src/plugins/post-action-hooks/AuthorizationTimePostActionHook.sol";
import {PostActionHookCombinator} from "../src/plugins/post-action-hooks/combinators/PostActionHookCombinator.sol";
import {
    PostActionHookCombinatorFactory
} from "../src/plugins/post-action-hooks/combinators/PostActionHookCombinatorFactory.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";
import {RefundRequestEvidence} from "../src/evidence/RefundRequestEvidence.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";

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
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertTrue(freezeAddr != address(0), "Freeze should be deployed");
    }

    function test_FreezeFactory_IdempotentDeploy() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address first = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        address second = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertEq(first, second, "Same config should return same address");
    }

    function test_FreezeFactory_GetDeployed() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

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
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address predicted = factory.computeAddress(address(payerCond), address(payerCond), 3 days, address(0));
        address actual = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_FreezeFactory_WithEscrowPeriod() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        EscrowPeriodFactory epFactory = new EscrowPeriodFactory(address(escrow));
        address ep = epFactory.deploy(7 days, bytes32(0));

        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, ep);
        assertTrue(freezeAddr != address(0), "Freeze with escrow period should be deployed");

        Freeze freezeContract = Freeze(freezeAddr);
        assertEq(address(freezeContract.ESCROW_PERIOD_CONTRACT()), ep, "Escrow period should match");
    }

    function test_FreezeFactory_DifferentConfigs() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address f1 = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        address f2 = factory.deploy(address(payerCond), address(payerCond), 7 days, address(0));
        assertTrue(f1 != f2, "Different durations should produce different addresses");
    }

    function test_FreezeFactory_DifferentConditions() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerPreActionCondition payerCond = new PayerPreActionCondition();
        ReceiverPreActionCondition receiverCond = new ReceiverPreActionCondition();

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
        PayerPreActionCondition payerCond = new PayerPreActionCondition();
        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 0, address(0));
        assertEq(Freeze(freezeAddr).FREEZE_DURATION(), 0, "Zero duration means permanent freeze");
    }

    function test_FreezeFactory_DeployedFreezeWorks() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerPreActionCondition payerCond = new PayerPreActionCondition();

        address freezeAddr = factory.deploy(address(payerCond), address(payerCond), 3 days, address(0));
        Freeze freezeContract = Freeze(freezeAddr);

        assertEq(address(freezeContract.FREEZE_PRE_ACTION_CONDITION()), address(payerCond));
        assertEq(address(freezeContract.UNFREEZE_PRE_ACTION_CONDITION()), address(payerCond));
        assertEq(freezeContract.FREEZE_DURATION(), 3 days);
    }

    // ============ AndPreActionConditionFactory ============

    function test_AndPreActionConditionFactory_Deploy() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](2);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));
        conds[1] = IPreActionCondition(address(new ReceiverPreActionCondition()));

        address deployed = factory.deploy(conds);
        assertTrue(deployed != address(0), "AndPreActionCondition should be deployed");
        assertEq(AndPreActionCondition(deployed).conditionCount(), 2, "Should have 2 conditions");
    }

    function test_AndPreActionConditionFactory_IdempotentDeploy() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        address first = factory.deploy(conds);
        address second = factory.deploy(conds);
        assertEq(first, second, "Same conditions should return same address");
    }

    function test_AndPreActionConditionFactory_ComputeAddress() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        address predicted = factory.computeAddress(conds);
        address actual = factory.deploy(conds);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_AndPreActionConditionFactory_GetDeployed() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        assertEq(factory.getDeployed(conds), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(conds);
        assertEq(factory.getDeployed(conds), deployed, "Should return deployed address");
    }

    function test_AndPreActionConditionFactory_NoConditions_Reverts() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](0);
        vm.expectRevert(AndPreActionConditionFactory.NoConditions.selector);
        factory.deploy(conds);
    }

    function test_AndPreActionConditionFactory_TooManyConditions_Reverts() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conds[i] = IPreActionCondition(address(new PayerPreActionCondition()));
        }
        vm.expectRevert(AndPreActionConditionFactory.TooManyConditions.selector);
        factory.deploy(conds);
    }

    function test_AndPreActionConditionFactory_GetKey() public {
        AndPreActionConditionFactory factory = new AndPreActionConditionFactory();
        IPreActionCondition[] memory conds1 = new IPreActionCondition[](1);
        conds1[0] = IPreActionCondition(address(new PayerPreActionCondition()));
        IPreActionCondition[] memory conds2 = new IPreActionCondition[](1);
        conds2[0] = IPreActionCondition(address(new ReceiverPreActionCondition()));

        bytes32 key1 = factory.getKey(conds1);
        bytes32 key2 = factory.getKey(conds2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ NotPreActionConditionFactory ============

    function test_NotPreActionConditionFactory_Deploy() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        IPreActionCondition cond = IPreActionCondition(address(new PayerPreActionCondition()));

        address deployed = factory.deploy(cond);
        assertTrue(deployed != address(0), "NotPreActionCondition should be deployed");
    }

    function test_NotPreActionConditionFactory_IdempotentDeploy() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        IPreActionCondition cond = IPreActionCondition(address(new PayerPreActionCondition()));

        address first = factory.deploy(cond);
        address second = factory.deploy(cond);
        assertEq(first, second, "Same condition should return same address");
    }

    function test_NotPreActionConditionFactory_ComputeAddress() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        IPreActionCondition cond = IPreActionCondition(address(new PayerPreActionCondition()));

        address predicted = factory.computeAddress(cond);
        address actual = factory.deploy(cond);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_NotPreActionConditionFactory_GetDeployed() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        IPreActionCondition cond = IPreActionCondition(address(new PayerPreActionCondition()));

        assertEq(factory.getDeployed(cond), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(cond);
        assertEq(factory.getDeployed(cond), deployed, "Should return deployed address");
    }

    function test_NotPreActionConditionFactory_ZeroCondition_Reverts() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        vm.expectRevert(NotPreActionConditionFactory.ZeroCondition.selector);
        factory.deploy(IPreActionCondition(address(0)));
    }

    function test_NotPreActionConditionFactory_GetKey() public {
        NotPreActionConditionFactory factory = new NotPreActionConditionFactory();
        IPreActionCondition cond1 = IPreActionCondition(address(new PayerPreActionCondition()));
        IPreActionCondition cond2 = IPreActionCondition(address(new ReceiverPreActionCondition()));

        bytes32 key1 = factory.getKey(cond1);
        bytes32 key2 = factory.getKey(cond2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ OrPreActionConditionFactory ============

    function test_OrPreActionConditionFactory_Deploy() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](2);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));
        conds[1] = IPreActionCondition(address(new ReceiverPreActionCondition()));

        address deployed = factory.deploy(conds);
        assertTrue(deployed != address(0), "OrPreActionCondition should be deployed");
        assertEq(OrPreActionCondition(deployed).conditionCount(), 2, "Should have 2 conditions");
    }

    function test_OrPreActionConditionFactory_IdempotentDeploy() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        address first = factory.deploy(conds);
        address second = factory.deploy(conds);
        assertEq(first, second, "Same conditions should return same address");
    }

    function test_OrPreActionConditionFactory_ComputeAddress() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        address predicted = factory.computeAddress(conds);
        address actual = factory.deploy(conds);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_OrPreActionConditionFactory_GetDeployed() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](1);
        conds[0] = IPreActionCondition(address(new PayerPreActionCondition()));

        assertEq(factory.getDeployed(conds), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(conds);
        assertEq(factory.getDeployed(conds), deployed, "Should return deployed address");
    }

    function test_OrPreActionConditionFactory_NoConditions_Reverts() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](0);
        vm.expectRevert(OrPreActionConditionFactory.NoConditions.selector);
        factory.deploy(conds);
    }

    function test_OrPreActionConditionFactory_TooManyConditions_Reverts() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds = new IPreActionCondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conds[i] = IPreActionCondition(address(new PayerPreActionCondition()));
        }
        vm.expectRevert(OrPreActionConditionFactory.TooManyConditions.selector);
        factory.deploy(conds);
    }

    function test_OrPreActionConditionFactory_GetKey() public {
        OrPreActionConditionFactory factory = new OrPreActionConditionFactory();
        IPreActionCondition[] memory conds1 = new IPreActionCondition[](1);
        conds1[0] = IPreActionCondition(address(new PayerPreActionCondition()));
        IPreActionCondition[] memory conds2 = new IPreActionCondition[](1);
        conds2[0] = IPreActionCondition(address(new ReceiverPreActionCondition()));

        bytes32 key1 = factory.getKey(conds1);
        bytes32 key2 = factory.getKey(conds2);
        assertTrue(key1 != key2, "Different conditions should produce different keys");
    }

    // ============ PostActionHookCombinatorFactory ============

    function test_PostActionHookCombinatorFactory_Deploy() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook[] memory recs = new IPostActionHook[](2);
        recs[0] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        recs[1] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));

        address deployed = factory.deploy(recs);
        assertTrue(deployed != address(0), "PostActionHookCombinator should be deployed");
        assertEq(PostActionHookCombinator(deployed).getHookCount(), 2, "Should have 2 hooks");
    }

    function test_PostActionHookCombinatorFactory_IdempotentDeploy() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook rec = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        IPostActionHook[] memory recs = new IPostActionHook[](1);
        recs[0] = rec;

        address first = factory.deploy(recs);
        address second = factory.deploy(recs);
        assertEq(first, second, "Same hooks should return same address");
    }

    function test_PostActionHookCombinatorFactory_ComputeAddress() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook[] memory recs = new IPostActionHook[](1);
        recs[0] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));

        address predicted = factory.computeAddress(recs);
        address actual = factory.deploy(recs);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_PostActionHookCombinatorFactory_GetDeployed() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook[] memory recs = new IPostActionHook[](1);
        recs[0] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));

        assertEq(factory.getDeployed(recs), address(0), "Should be zero before deployment");
        address deployed = factory.deploy(recs);
        assertEq(factory.getDeployed(recs), deployed, "Should return deployed address");
    }

    function test_PostActionHookCombinatorFactory_EmptyHooks_Reverts() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook[] memory recs = new IPostActionHook[](0);
        vm.expectRevert(PostActionHookCombinatorFactory.EmptyHooks.selector);
        factory.deploy(recs);
    }

    function test_PostActionHookCombinatorFactory_TooManyHooks_Reverts() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook[] memory recs = new IPostActionHook[](11);
        for (uint256 i = 0; i < 11; i++) {
            recs[i] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        }
        vm.expectRevert(PostActionHookCombinatorFactory.TooManyHooks.selector);
        factory.deploy(recs);
    }

    function test_PostActionHookCombinatorFactory_GetKey() public {
        PostActionHookCombinatorFactory factory = new PostActionHookCombinatorFactory();
        IPostActionHook rec1 =
            IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        IPostActionHook rec2 =
            IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        IPostActionHook[] memory recs1 = new IPostActionHook[](1);
        recs1[0] = rec1;
        IPostActionHook[] memory recs2 = new IPostActionHook[](1);
        recs2[0] = rec2;

        bytes32 key1 = factory.getKey(recs1);
        bytes32 key2 = factory.getKey(recs2);
        assertTrue(key1 != key2, "Different hooks should produce different keys");
    }

    // ============ PaymentOperatorFactory ============

    function test_PaymentOperatorFactory_DifferentConfigs() public {
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config1 = _defaultConfig(address(0));
        PaymentOperatorFactory.OperatorConfig memory config2 = _defaultConfig(address(0));
        config2.feeReceiver = makeAddr("otherRecipient");

        address op1 = factory.deployOperator(config1);
        address op2 = factory.deployOperator(config2);
        assertTrue(op1 != op2, "Different configs should produce different operators");
    }

    function test_PaymentOperatorFactory_ImmutableFields() public {
        PaymentOperatorFactory factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        assertEq(address(factory.ESCROW()), address(escrow), "ESCROW should be immutable");
        assertEq(address(factory.PROTOCOL_FEE_CONFIG()), address(protocolFeeConfig), "FEE_CONFIG should be immutable");
    }

    // ============ RefundRequestEvidenceFactory ============

    function test_RefundRequestEvidenceFactory_Deploy() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        address refundRequest = address(new RefundRequest(makeAddr("arbiter")));

        address evidence = factory.deploy(refundRequest);
        assertTrue(evidence != address(0), "Evidence should be deployed");
        assertEq(address(RefundRequestEvidence(evidence).REFUND_REQUEST()), refundRequest, "RefundRequest should match");
    }

    function test_RefundRequestEvidenceFactory_IdempotentDeploy() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        address refundRequest = address(new RefundRequest(makeAddr("arbiter")));

        address first = factory.deploy(refundRequest);
        address second = factory.deploy(refundRequest);
        assertEq(first, second, "Same refundRequest should return same address");
    }

    function test_RefundRequestEvidenceFactory_DifferentRefundRequests() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        address rr1 = address(new RefundRequest(makeAddr("arbiter1")));
        address rr2 = address(new RefundRequest(makeAddr("arbiter2")));

        address ev1 = factory.deploy(rr1);
        address ev2 = factory.deploy(rr2);
        assertTrue(ev1 != ev2, "Different refundRequests should produce different addresses");
    }

    function test_RefundRequestEvidenceFactory_ComputeAddress() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        address refundRequest = address(new RefundRequest(makeAddr("arbiter")));

        address predicted = factory.computeAddress(refundRequest);
        address actual = factory.deploy(refundRequest);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_RefundRequestEvidenceFactory_GetDeployed() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        address refundRequest = address(new RefundRequest(makeAddr("arbiter")));

        assertEq(factory.getDeployed(refundRequest), address(0), "Should be zero before deployment");
        address evidence = factory.deploy(refundRequest);
        assertEq(factory.getDeployed(refundRequest), evidence, "Should return deployed address");
    }

    function test_RefundRequestEvidenceFactory_ZeroRefundRequest_Reverts() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        vm.expectRevert(RefundRequestEvidenceFactory.ZeroRefundRequest.selector);
        factory.deploy(address(0));
    }

    function test_RefundRequestEvidenceFactory_GetKey() public {
        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();
        bytes32 key1 = factory.getKey(address(1));
        bytes32 key2 = factory.getKey(address(2));
        assertTrue(key1 != key2, "Different addresses should produce different keys");
        assertEq(key1, factory.getKey(address(1)), "Same address should produce same key");
    }

    // ============ Helpers ============

    function _defaultConfig(address feeCalc) internal view returns (PaymentOperatorFactory.OperatorConfig memory) {
        return PaymentOperatorFactory.OperatorConfig({
            feeReceiver: protocolFeeRecipient,
            feeCalculator: feeCalc,
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
    }
}
