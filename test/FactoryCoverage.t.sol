// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/StaticFeeCalculator.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/StaticFeeCalculatorFactory.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {Freeze} from "../src/plugins/freeze/Freeze.sol";
import {FreezePolicyFactory} from "../src/plugins/freeze/freeze-policy/FreezePolicyFactory.sol";
import {FreezePolicy} from "../src/plugins/freeze/freeze-policy/FreezePolicy.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";

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
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 3 days);

        address freezeAddr = factory.deploy(address(freezePolicy), address(0));
        assertTrue(freezeAddr != address(0), "Freeze should be deployed");
    }

    function test_FreezeFactory_IdempotentDeploy() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 3 days);

        address first = factory.deploy(address(freezePolicy), address(0));
        address second = factory.deploy(address(freezePolicy), address(0));
        assertEq(first, second, "Same config should return same address");
    }

    function test_FreezeFactory_GetDeployed() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 3 days);

        assertEq(factory.getDeployed(address(freezePolicy), address(0)), address(0), "Should be zero before deployment");

        address deployed = factory.deploy(address(freezePolicy), address(0));
        assertEq(factory.getDeployed(address(freezePolicy), address(0)), deployed, "Should return deployed address");
    }

    function test_FreezeFactory_ComputeAddress() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 3 days);

        address predicted = factory.computeAddress(address(freezePolicy), address(0));
        address actual = factory.deploy(address(freezePolicy), address(0));
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_FreezeFactory_WithEscrowPeriod() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        EscrowPeriodFactory epFactory = new EscrowPeriodFactory(address(escrow));
        address ep = epFactory.deploy(7 days, bytes32(0));

        PayerCondition payerCond = new PayerCondition();
        FreezePolicy freezePolicy = new FreezePolicy(address(payerCond), address(payerCond), 3 days);

        address freezeAddr = factory.deploy(address(freezePolicy), ep);
        assertTrue(freezeAddr != address(0), "Freeze with escrow period should be deployed");

        Freeze freezeContract = Freeze(freezeAddr);
        assertEq(address(freezeContract.ESCROW_PERIOD_CONTRACT()), ep, "Escrow period should match");
    }

    function test_FreezeFactory_DifferentConfigs() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        PayerCondition payerCond = new PayerCondition();
        FreezePolicy fp1 = new FreezePolicy(address(payerCond), address(payerCond), 3 days);
        FreezePolicy fp2 = new FreezePolicy(address(payerCond), address(payerCond), 7 days);

        address f1 = factory.deploy(address(fp1), address(0));
        address f2 = factory.deploy(address(fp2), address(0));
        assertTrue(f1 != f2, "Different policies should produce different addresses");
    }

    function test_FreezeFactory_GetKey() public {
        FreezeFactory factory = new FreezeFactory(address(escrow));
        bytes32 key1 = factory.getKey(address(1), address(0));
        bytes32 key2 = factory.getKey(address(2), address(0));
        assertTrue(key1 != key2, "Different configs should produce different keys");
    }

    function test_FreezeFactory_ZeroEscrow_Reverts() public {
        vm.expectRevert();
        new FreezeFactory(address(0));
    }

    // ============ FreezePolicyFactory ============

    function test_FreezePolicyFactory_Deploy() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();

        address policy = factory.deploy(address(payerCond), address(payerCond), 3 days);
        assertTrue(policy != address(0), "Policy should be deployed");
        assertEq(FreezePolicy(policy).FREEZE_DURATION(), 3 days, "Duration should match");
    }

    function test_FreezePolicyFactory_IdempotentDeploy() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();

        address first = factory.deploy(address(payerCond), address(payerCond), 3 days);
        address second = factory.deploy(address(payerCond), address(payerCond), 3 days);
        assertEq(first, second, "Same config should return same address");
    }

    function test_FreezePolicyFactory_GetDeployed() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();

        assertEq(
            factory.getDeployed(address(payerCond), address(payerCond), 3 days),
            address(0),
            "Should be zero before deployment"
        );
        address policy = factory.deploy(address(payerCond), address(payerCond), 3 days);
        assertEq(
            factory.getDeployed(address(payerCond), address(payerCond), 3 days),
            policy,
            "Should return deployed address"
        );
    }

    function test_FreezePolicyFactory_ComputeAddress() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();

        address predicted = factory.computeAddress(address(payerCond), address(payerCond), 3 days);
        address actual = factory.deploy(address(payerCond), address(payerCond), 3 days);
        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_FreezePolicyFactory_DifferentDurations() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();

        address p1 = factory.deploy(address(payerCond), address(payerCond), 3 days);
        address p2 = factory.deploy(address(payerCond), address(payerCond), 7 days);
        assertTrue(p1 != p2, "Different durations should produce different addresses");
    }

    function test_FreezePolicyFactory_DifferentConditions() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();
        ReceiverCondition receiverCond = new ReceiverCondition();

        address p1 = factory.deploy(address(payerCond), address(payerCond), 3 days);
        address p2 = factory.deploy(address(payerCond), address(receiverCond), 3 days);
        assertTrue(p1 != p2, "Different conditions should produce different addresses");
    }

    function test_FreezePolicyFactory_GetKey() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();
        bytes32 key1 = factory.getKey(address(payerCond), address(payerCond), 3 days);
        bytes32 key2 = factory.getKey(address(payerCond), address(payerCond), 7 days);
        assertTrue(key1 != key2, "Different configs should produce different keys");
    }

    function test_FreezePolicyFactory_ZeroDuration() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();
        PayerCondition payerCond = new PayerCondition();
        address policy = factory.deploy(address(payerCond), address(payerCond), 0);
        assertEq(FreezePolicy(policy).FREEZE_DURATION(), 0, "Zero duration means permanent freeze");
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
