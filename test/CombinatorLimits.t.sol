// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ICondition} from "../src/plugins/conditions/ICondition.sol";
import {IRecorder} from "../src/plugins/recorders/IRecorder.sol";
import {AndCondition} from "../src/plugins/conditions/combinators/AndCondition.sol";
import {OrCondition} from "../src/plugins/conditions/combinators/OrCondition.sol";
import {NotCondition} from "../src/plugins/conditions/combinators/NotCondition.sol";
import {RecorderCombinator} from "../src/plugins/recorders/combinators/RecorderCombinator.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {AuthorizationTimeRecorder} from "../src/plugins/recorders/AuthorizationTimeRecorder.sol";

/**
 * @title CombinatorLimitsTest
 * @notice Tests for condition combinator array length limits and nesting
 * @dev Ensures MAX_CONDITIONS (10) / MAX_RECORDERS (10) are enforced,
 *      and nested combinators (Not wrapping And/Or) behave correctly
 */
contract CombinatorLimitsTest is Test {
    AlwaysTrueCondition public alwaysTrue;
    PayerCondition public payerCond;
    AuthCaptureEscrow public escrow;

    function setUp() public {
        alwaysTrue = new AlwaysTrueCondition();
        payerCond = new PayerCondition();
        escrow = new AuthCaptureEscrow();
    }

    // ============ AndCondition Tests ============

    function test_AndCondition_AcceptsMaxConditions() public {
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should succeed with exactly MAX_CONDITIONS (10)
        AndCondition andCond = new AndCondition(conditions);
        assertEq(andCond.conditionCount(), 10);
    }

    function test_AndCondition_RevertsOnTooManyConditions() public {
        ICondition[] memory conditions = new ICondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should revert with TooManyConditions
        vm.expectRevert(AndCondition.TooManyConditions.selector);
        new AndCondition(conditions);
    }

    function test_AndCondition_RevertsOnNoConditions() public {
        ICondition[] memory conditions = new ICondition[](0);

        // Should revert with NoConditions
        vm.expectRevert(AndCondition.NoConditions.selector);
        new AndCondition(conditions);
    }

    // ============ OrCondition Tests ============

    function test_OrCondition_AcceptsMaxConditions() public {
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should succeed with exactly MAX_CONDITIONS (10)
        OrCondition orCond = new OrCondition(conditions);
        assertEq(orCond.conditionCount(), 10);
    }

    function test_OrCondition_RevertsOnTooManyConditions() public {
        ICondition[] memory conditions = new ICondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should revert with TooManyConditions
        vm.expectRevert(OrCondition.TooManyConditions.selector);
        new OrCondition(conditions);
    }

    function test_OrCondition_RevertsOnNoConditions() public {
        ICondition[] memory conditions = new ICondition[](0);

        // Should revert with NoConditions
        vm.expectRevert(OrCondition.NoConditions.selector);
        new OrCondition(conditions);
    }

    // ============ MAX_CONDITIONS Constant Tests ============

    function test_MaxConditionsConstant() public {
        ICondition[] memory conditions = new ICondition[](1);
        conditions[0] = alwaysTrue;

        AndCondition andCond = new AndCondition(conditions);
        OrCondition orCond = new OrCondition(conditions);

        // Verify MAX_CONDITIONS is 10 for both
        assertEq(andCond.MAX_CONDITIONS(), 10);
        assertEq(orCond.MAX_CONDITIONS(), 10);
    }

    // ============ NotCondition Wrapping Combinator Tests ============

    function test_NotCondition_WrapsAndCondition() public {
        // Not(And(10 conditions)) = 11 total depth
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndCondition andCond = new AndCondition(conditions);
        NotCondition notCond = new NotCondition(andCond);

        // And(10 AlwaysTrue) = true, Not(true) = false
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        bool result = notCond.check(paymentInfo, 0, address(this));
        assertFalse(result, "Not(And(10 AlwaysTrue)) should be false");
    }

    function test_NotCondition_WrapsOrCondition() public {
        // Not(Or(10 conditions)) = 11 total depth
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        OrCondition orCond = new OrCondition(conditions);
        NotCondition notCond = new NotCondition(orCond);

        // Or(10 AlwaysTrue) = true, Not(true) = false
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        bool result = notCond.check(paymentInfo, 0, address(this));
        assertFalse(result, "Not(Or(10 AlwaysTrue)) should be false");
    }

    function test_NotCondition_WrapsAndCondition_WithFalseInner() public {
        // PayerCondition returns false when caller != payer
        ICondition[] memory conditions = new ICondition[](2);
        conditions[0] = alwaysTrue;
        conditions[1] = payerCond; // Will return false for address(this)

        AndCondition andCond = new AndCondition(conditions);
        NotCondition notCond = new NotCondition(andCond);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        // And(AlwaysTrue, PayerCond) = false (caller != payer), Not(false) = true
        bool result = notCond.check(paymentInfo, 0, address(this));
        assertTrue(result, "Not(And(AlwaysTrue, PayerCond)) should be true when caller != payer");
    }

    function test_AndCondition_ShortCircuitsOnFirstFalse() public {
        // Place a false condition first, followed by 9 true conditions
        // Short-circuit should return false without evaluating all 10
        ICondition[] memory conditions = new ICondition[](10);
        conditions[0] = payerCond; // Returns false for non-payer caller
        for (uint256 i = 1; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndCondition andCond = new AndCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        // Measure gas - short-circuit should use less gas than evaluating all 10
        uint256 gasBefore = gasleft();
        bool result = andCond.check(paymentInfo, 0, address(this));
        uint256 gasUsed = gasBefore - gasleft();

        assertFalse(result, "Should return false on first condition");
        // Gas should be relatively low since only 1 condition is evaluated
        // A single condition check costs ~2k-5k gas; all 10 would cost ~20k-50k
        assertLt(gasUsed, 15000, "Short-circuit should use less gas than evaluating all conditions");
    }

    function test_OrCondition_ShortCircuitsOnFirstTrue() public {
        // Place a true condition first, followed by 9 conditions
        // Short-circuit should return true without evaluating the rest
        ICondition[] memory conditions = new ICondition[](10);
        conditions[0] = alwaysTrue; // Returns true immediately
        for (uint256 i = 1; i < 10; i++) {
            conditions[i] = payerCond;
        }

        OrCondition orCond = new OrCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = orCond.check(paymentInfo, 0, address(this));
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result, "Should return true on first condition");
        assertLt(gasUsed, 15000, "Short-circuit should use less gas than evaluating all conditions");
    }

    // ============ Gas Analysis Tests ============

    function test_GasAnalysis_AndCondition_MaxDepth() public {
        // 10 AlwaysTrue conditions — all must be evaluated (no short-circuit)
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndCondition andCond = new AndCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = andCond.check(paymentInfo, 0, address(this));
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result, "And(10 AlwaysTrue) should be true");
        assertLt(gasUsed, 100000, "And(10 conditions) must use < 100k gas");
    }

    function test_GasAnalysis_OrCondition_MaxDepth_AllFalse() public {
        // 10 PayerConditions (all false for address(this)) — worst case, no short-circuit
        ICondition[] memory conditions = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = payerCond;
        }

        OrCondition orCond = new OrCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = orCond.check(paymentInfo, 0, address(this));
        uint256 gasUsed = gasBefore - gasleft();

        assertFalse(result, "Or(10 PayerCond) should be false for non-payer");
        assertLt(gasUsed, 100000, "Or(10 conditions, all false) must use < 100k gas");
    }

    function test_GasAnalysis_NestedCombinator() public {
        // Not(And(10 x Or(10))) = 100 leaf checks
        // Each inner Or has 10 AlwaysTrue conditions, so Or returns true immediately (short-circuit)
        // But And needs all 10 Or results = true, evaluating at least 10 inner checks
        ICondition[] memory innerOrs = new ICondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            ICondition[] memory orConditions = new ICondition[](10);
            for (uint256 j = 0; j < 10; j++) {
                orConditions[j] = alwaysTrue;
            }
            innerOrs[i] = ICondition(address(new OrCondition(orConditions)));
        }

        AndCondition andCond = new AndCondition(innerOrs);
        NotCondition notCond = new NotCondition(andCond);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = notCond.check(paymentInfo, 0, address(this));
        uint256 gasUsed = gasBefore - gasleft();

        // And(10 x Or(10 AlwaysTrue)) = true, Not(true) = false
        assertFalse(result, "Not(And(10 x Or(10 AlwaysTrue))) should be false");
        assertLt(gasUsed, 1000000, "Nested combinator (100 leaf) must use < 1M gas");
    }

    // ============ RecorderCombinator Limit Tests ============

    function test_RecorderCombinator_AcceptsMaxRecorders() public {
        IRecorder[] memory recs = new IRecorder[](10);
        for (uint256 i = 0; i < 10; i++) {
            recs[i] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        }

        RecorderCombinator combinator = new RecorderCombinator(recs);
        assertEq(combinator.getRecorderCount(), 10, "Should accept exactly MAX_RECORDERS (10)");
    }

    function test_RecorderCombinator_RevertsOnTooManyRecorders() public {
        IRecorder[] memory recs = new IRecorder[](11);
        for (uint256 i = 0; i < 11; i++) {
            recs[i] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));
        }

        vm.expectRevert(abi.encodeWithSelector(RecorderCombinator.TooManyRecorders.selector, 11, 10));
        new RecorderCombinator(recs);
    }

    function test_RecorderCombinator_RevertsOnEmptyRecorders() public {
        IRecorder[] memory recs = new IRecorder[](0);

        vm.expectRevert(RecorderCombinator.EmptyRecorders.selector);
        new RecorderCombinator(recs);
    }

    function test_RecorderCombinator_MaxRecordersConstant() public {
        IRecorder[] memory recs = new IRecorder[](1);
        recs[0] = IRecorder(address(new AuthorizationTimeRecorder(address(escrow), bytes32(0))));

        RecorderCombinator combinator = new RecorderCombinator(recs);
        assertEq(combinator.MAX_RECORDERS(), 10, "MAX_RECORDERS should be 10");
    }

    // ============ Helpers ============

    function _dummyPaymentInfo() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(this),
            payer: makeAddr("payer"),
            receiver: makeAddr("receiver"),
            token: address(0),
            maxAmount: 1000,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(this),
            salt: 0
        });
    }
}
