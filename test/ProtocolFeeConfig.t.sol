// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/fees/StaticFeeCalculator.sol";
import {IFeeCalculator} from "../src/fees/IFeeCalculator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

contract ProtocolFeeConfigTest is Test {
    ProtocolFeeConfig public config;
    StaticFeeCalculator public calculator;

    address public owner;
    address public protocolFeeRecipient;
    address public newRecipient;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        newRecipient = makeAddr("newRecipient");

        calculator = new StaticFeeCalculator(25); // 25 bps
        config = new ProtocolFeeConfig(address(calculator), protocolFeeRecipient, owner);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsValues() public view {
        assertEq(address(config.calculator()), address(calculator));
        assertEq(config.protocolFeeRecipient(), protocolFeeRecipient);
        assertEq(config.owner(), owner);
    }

    function test_Constructor_ZeroCalculator() public {
        ProtocolFeeConfig c = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        assertEq(address(c.calculator()), address(0));
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert();
        new ProtocolFeeConfig(address(calculator), protocolFeeRecipient, address(0));
    }

    function test_Constructor_RevertsOnZeroRecipient() public {
        vm.expectRevert();
        new ProtocolFeeConfig(address(calculator), address(0), owner);
    }

    // ============ getProtocolFeeBps Tests ============

    function test_GetProtocolFeeBps_ReturnsCalculatorValue() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        uint256 feeBps = config.getProtocolFeeBps(paymentInfo, 1000, address(this));
        assertEq(feeBps, 25, "Should return calculator value");
    }

    function test_GetProtocolFeeBps_ReturnsZeroWhenNoCalculator() public {
        ProtocolFeeConfig c = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        uint256 feeBps = c.getProtocolFeeBps(paymentInfo, 1000, address(this));
        assertEq(feeBps, 0, "Should return 0 when no calculator");
    }

    // ============ getProtocolFeeRecipient Tests ============

    function test_GetProtocolFeeRecipient() public view {
        assertEq(config.getProtocolFeeRecipient(), protocolFeeRecipient);
    }

    // ============ setProtocolFeeRecipient Tests ============

    function test_SetProtocolFeeRecipient() public {
        config.setProtocolFeeRecipient(newRecipient);
        assertEq(config.getProtocolFeeRecipient(), newRecipient);
    }

    function test_SetProtocolFeeRecipient_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit ProtocolFeeConfig.ProtocolFeeRecipientUpdated(newRecipient);
        config.setProtocolFeeRecipient(newRecipient);
    }

    function test_SetProtocolFeeRecipient_RevertsIfNotOwner() public {
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        config.setProtocolFeeRecipient(newRecipient);
    }

    function test_SetProtocolFeeRecipient_RevertsOnZeroAddress() public {
        vm.expectRevert();
        config.setProtocolFeeRecipient(address(0));
    }

    // ============ Timelock: queueCalculator Tests ============

    function test_QueueCalculator() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        assertEq(config.pendingCalculator(), address(newCalc));
        assertEq(config.pendingCalculatorTimestamp(), block.timestamp + 7 days);
    }

    function test_QueueCalculator_EmitsEvent() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);

        vm.expectEmit(true, false, false, true);
        emit ProtocolFeeConfig.CalculatorChangeQueued(address(newCalc), block.timestamp + 7 days);
        config.queueCalculator(address(newCalc));
    }

    function test_QueueCalculator_AllowsZeroAddress() public {
        config.queueCalculator(address(0));
        assertEq(config.pendingCalculator(), address(0));
    }

    function test_QueueCalculator_RevertsIfNotOwner() public {
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        config.queueCalculator(address(0));
    }

    // ============ Timelock: executeCalculator Tests ============

    function test_ExecuteCalculator_AfterTimelock() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.warp(block.timestamp + 7 days);
        config.executeCalculator();

        assertEq(address(config.calculator()), address(newCalc));
        assertEq(config.pendingCalculatorTimestamp(), 0);
        assertEq(config.pendingCalculator(), address(0));
    }

    function test_ExecuteCalculator_EmitsEvent() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, false, false, false);
        emit ProtocolFeeConfig.CalculatorChangeExecuted(address(newCalc));
        config.executeCalculator();
    }

    function test_ExecuteCalculator_RevertsBeforeTimelock() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.warp(block.timestamp + 7 days - 1);

        vm.expectRevert(ProtocolFeeConfig.CalculatorTimelockNotElapsed.selector);
        config.executeCalculator();
    }

    function test_ExecuteCalculator_RevertsIfNoPending() public {
        vm.expectRevert(ProtocolFeeConfig.NoPendingCalculatorChange.selector);
        config.executeCalculator();
    }

    function test_ExecuteCalculator_RevertsIfNotOwner() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.warp(block.timestamp + 7 days);

        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        config.executeCalculator();
    }

    function test_ExecuteCalculator_ToZeroDisablesFees() public {
        config.queueCalculator(address(0));

        vm.warp(block.timestamp + 7 days);
        config.executeCalculator();

        assertEq(address(config.calculator()), address(0));

        // Verify fees now return 0
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        uint256 feeBps = config.getProtocolFeeBps(paymentInfo, 1000, address(this));
        assertEq(feeBps, 0, "Should return 0 after disabling calculator");
    }

    // ============ Timelock: cancelCalculator Tests ============

    function test_CancelCalculator() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        config.cancelCalculator();

        assertEq(config.pendingCalculator(), address(0));
        assertEq(config.pendingCalculatorTimestamp(), 0);
        // Original calculator unchanged
        assertEq(address(config.calculator()), address(calculator));
    }

    function test_CancelCalculator_EmitsEvent() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.expectEmit(false, false, false, false);
        emit ProtocolFeeConfig.CalculatorChangeCancelled();
        config.cancelCalculator();
    }

    function test_CancelCalculator_RevertsIfNoPending() public {
        vm.expectRevert(ProtocolFeeConfig.NoPendingCalculatorChange.selector);
        config.cancelCalculator();
    }

    function test_CancelCalculator_RevertsIfNotOwner() public {
        StaticFeeCalculator newCalc = new StaticFeeCalculator(50);
        config.queueCalculator(address(newCalc));

        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        config.cancelCalculator();
    }

    // ============ Calculator Swap Full Flow ============

    function test_CalculatorSwap_FullFlow() public {
        // Start with 25 bps calculator
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertEq(config.getProtocolFeeBps(paymentInfo, 1000, address(this)), 25);

        // Queue swap to 100 bps
        StaticFeeCalculator newCalc = new StaticFeeCalculator(100);
        config.queueCalculator(address(newCalc));

        // Still 25 bps during timelock
        assertEq(config.getProtocolFeeBps(paymentInfo, 1000, address(this)), 25);

        // Execute after timelock
        vm.warp(block.timestamp + 7 days);
        config.executeCalculator();

        // Now 100 bps
        assertEq(config.getProtocolFeeBps(paymentInfo, 1000, address(this)), 100);
    }

    // ============ Helper ============

    function _createPaymentInfo() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(this),
            payer: makeAddr("configTestPayer"),
            receiver: makeAddr("configTestReceiver"),
            token: address(0),
            maxAmount: 1000,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 100,
            feeReceiver: address(this),
            salt: 12345
        });
    }
}
