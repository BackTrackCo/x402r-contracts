// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPreActionCondition} from "../src/plugins/pre-action-conditions/IPreActionCondition.sol";
import {IPostActionHook} from "../src/plugins/post-action-hooks/IPostActionHook.sol";
import {AndPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/AndPreActionCondition.sol";
import {OrPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/OrPreActionCondition.sol";
import {NotPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/NotPreActionCondition.sol";
import {PostActionHookCombinator} from "../src/plugins/post-action-hooks/combinators/PostActionHookCombinator.sol";
import {
    AlwaysTruePreActionCondition
} from "../src/plugins/pre-action-conditions/access/AlwaysTruePreActionCondition.sol";
import {PayerPreActionCondition} from "../src/plugins/pre-action-conditions/access/PayerPreActionCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {AuthorizationTimePostActionHook} from "../src/plugins/post-action-hooks/AuthorizationTimePostActionHook.sol";

/**
 * @title CombinatorLimitsTest
 * @notice Tests for condition combinator array length limits and nesting
 * @dev Ensures MAX_PRE_ACTION_CONDITIONS (10) / MAX_POST_ACTION_HOOKS (10) are enforced,
 *      and nested combinators (Not wrapping And/Or) behave correctly
 */
contract CombinatorLimitsTest is Test {
    AlwaysTruePreActionCondition public alwaysTrue;
    PayerPreActionCondition public payerCond;
    AuthCaptureEscrow public escrow;

    function setUp() public {
        alwaysTrue = new AlwaysTruePreActionCondition();
        payerCond = new PayerPreActionCondition();
        escrow = new AuthCaptureEscrow();
    }

    // ============ AndPreActionCondition Tests ============

    function test_AndPreActionCondition_AcceptsMaxConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should succeed with exactly MAX_PRE_ACTION_CONDITIONS (10)
        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        assertEq(andCond.conditionCount(), 10);
    }

    function test_AndPreActionCondition_RevertsOnTooManyConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should revert with TooManyConditions
        vm.expectRevert(AndPreActionCondition.TooManyConditions.selector);
        new AndPreActionCondition(conditions);
    }

    function test_AndPreActionCondition_RevertsOnNoConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](0);

        // Should revert with NoConditions
        vm.expectRevert(AndPreActionCondition.NoConditions.selector);
        new AndPreActionCondition(conditions);
    }

    // ============ OrPreActionCondition Tests ============

    function test_OrPreActionCondition_AcceptsMaxConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should succeed with exactly MAX_PRE_ACTION_CONDITIONS (10)
        OrPreActionCondition orCond = new OrPreActionCondition(conditions);
        assertEq(orCond.conditionCount(), 10);
    }

    function test_OrPreActionCondition_RevertsOnTooManyConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](11);
        for (uint256 i = 0; i < 11; i++) {
            conditions[i] = alwaysTrue;
        }

        // Should revert with TooManyConditions
        vm.expectRevert(OrPreActionCondition.TooManyConditions.selector);
        new OrPreActionCondition(conditions);
    }

    function test_OrPreActionCondition_RevertsOnNoConditions() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](0);

        // Should revert with NoConditions
        vm.expectRevert(OrPreActionCondition.NoConditions.selector);
        new OrPreActionCondition(conditions);
    }

    // ============ MAX_PRE_ACTION_CONDITIONS Constant Tests ============

    function test_MaxConditionsConstant() public {
        IPreActionCondition[] memory conditions = new IPreActionCondition[](1);
        conditions[0] = alwaysTrue;

        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        OrPreActionCondition orCond = new OrPreActionCondition(conditions);

        // Verify MAX_PRE_ACTION_CONDITIONS is 10 for both
        assertEq(andCond.MAX_PRE_ACTION_CONDITIONS(), 10);
        assertEq(orCond.MAX_PRE_ACTION_CONDITIONS(), 10);
    }

    // ============ NotPreActionCondition Wrapping Combinator Tests ============

    function test_NotPreActionCondition_WrapsAndPreActionCondition() public {
        // Not(And(10 conditions)) = 11 total depth
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        NotPreActionCondition notCond = new NotPreActionCondition(andCond);

        // And(10 AlwaysTrue) = true, Not(true) = false
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        bool result = notCond.check(paymentInfo, 0, address(this), "");
        assertFalse(result, "Not(And(10 AlwaysTrue)) should be false");
    }

    function test_NotPreActionCondition_WrapsOrPreActionCondition() public {
        // Not(Or(10 conditions)) = 11 total depth
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        OrPreActionCondition orCond = new OrPreActionCondition(conditions);
        NotPreActionCondition notCond = new NotPreActionCondition(orCond);

        // Or(10 AlwaysTrue) = true, Not(true) = false
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        bool result = notCond.check(paymentInfo, 0, address(this), "");
        assertFalse(result, "Not(Or(10 AlwaysTrue)) should be false");
    }

    function test_NotPreActionCondition_WrapsAndPreActionCondition_WithFalseInner() public {
        // PayerPreActionCondition returns false when caller != payer
        IPreActionCondition[] memory conditions = new IPreActionCondition[](2);
        conditions[0] = alwaysTrue;
        conditions[1] = payerCond; // Will return false for address(this)

        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        NotPreActionCondition notCond = new NotPreActionCondition(andCond);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();
        // And(AlwaysTrue, PayerCond) = false (caller != payer), Not(false) = true
        bool result = notCond.check(paymentInfo, 0, address(this), "");
        assertTrue(result, "Not(And(AlwaysTrue, PayerCond)) should be true when caller != payer");
    }

    function test_AndPreActionCondition_ShortCircuitsOnFirstFalse() public {
        // Place a false condition first, followed by 9 true conditions
        // Short-circuit should return false without evaluating all 10
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        conditions[0] = payerCond; // Returns false for non-payer caller
        for (uint256 i = 1; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        // Measure gas - short-circuit should use less gas than evaluating all 10
        uint256 gasBefore = gasleft();
        bool result = andCond.check(paymentInfo, 0, address(this), "");
        uint256 gasUsed = gasBefore - gasleft();

        assertFalse(result, "Should return false on first condition");
        // Gas should be relatively low since only 1 condition is evaluated
        // A single condition check costs ~2k-5k gas; all 10 would cost ~20k-50k
        assertLt(gasUsed, 15000, "Short-circuit should use less gas than evaluating all conditions");
    }

    function test_OrPreActionCondition_ShortCircuitsOnFirstTrue() public {
        // Place a true condition first, followed by 9 conditions
        // Short-circuit should return true without evaluating the rest
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        conditions[0] = alwaysTrue; // Returns true immediately
        for (uint256 i = 1; i < 10; i++) {
            conditions[i] = payerCond;
        }

        OrPreActionCondition orCond = new OrPreActionCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = orCond.check(paymentInfo, 0, address(this), "");
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result, "Should return true on first condition");
        assertLt(gasUsed, 15000, "Short-circuit should use less gas than evaluating all conditions");
    }

    // ============ Gas Analysis Tests ============

    function test_GasAnalysis_AndPreActionCondition_MaxDepth() public {
        // 10 AlwaysTrue conditions — all must be evaluated (no short-circuit)
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = alwaysTrue;
        }

        AndPreActionCondition andCond = new AndPreActionCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = andCond.check(paymentInfo, 0, address(this), "");
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result, "And(10 AlwaysTrue) should be true");
        assertLt(gasUsed, 100000, "And(10 conditions) must use < 100k gas");
    }

    function test_GasAnalysis_OrPreActionCondition_MaxDepth_AllFalse() public {
        // 10 PayerPreActionConditions (all false for address(this)) — worst case, no short-circuit
        IPreActionCondition[] memory conditions = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            conditions[i] = payerCond;
        }

        OrPreActionCondition orCond = new OrPreActionCondition(conditions);
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = orCond.check(paymentInfo, 0, address(this), "");
        uint256 gasUsed = gasBefore - gasleft();

        assertFalse(result, "Or(10 PayerCond) should be false for non-payer");
        assertLt(gasUsed, 100000, "Or(10 conditions, all false) must use < 100k gas");
    }

    function test_GasAnalysis_NestedCombinator() public {
        // Not(And(10 x Or(10))) = 100 leaf checks
        // Each inner Or has 10 AlwaysTrue conditions, so Or returns true immediately (short-circuit)
        // But And needs all 10 Or results = true, evaluating at least 10 inner checks
        IPreActionCondition[] memory innerOrs = new IPreActionCondition[](10);
        for (uint256 i = 0; i < 10; i++) {
            IPreActionCondition[] memory orConditions = new IPreActionCondition[](10);
            for (uint256 j = 0; j < 10; j++) {
                orConditions[j] = alwaysTrue;
            }
            innerOrs[i] = IPreActionCondition(address(new OrPreActionCondition(orConditions)));
        }

        AndPreActionCondition andCond = new AndPreActionCondition(innerOrs);
        NotPreActionCondition notCond = new NotPreActionCondition(andCond);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _dummyPaymentInfo();

        uint256 gasBefore = gasleft();
        bool result = notCond.check(paymentInfo, 0, address(this), "");
        uint256 gasUsed = gasBefore - gasleft();

        // And(10 x Or(10 AlwaysTrue)) = true, Not(true) = false
        assertFalse(result, "Not(And(10 x Or(10 AlwaysTrue))) should be false");
        assertLt(gasUsed, 1000000, "Nested combinator (100 leaf) must use < 1M gas");
    }

    // ============ PostActionHookCombinator Limit Tests ============

    function test_PostActionHookCombinator_AcceptsMaxHooks() public {
        IPostActionHook[] memory recs = new IPostActionHook[](10);
        for (uint256 i = 0; i < 10; i++) {
            recs[i] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        }

        PostActionHookCombinator combinator = new PostActionHookCombinator(recs);
        assertEq(combinator.getHookCount(), 10, "Should accept exactly MAX_POST_ACTION_HOOKS (10)");
    }

    function test_PostActionHookCombinator_RevertsOnTooManyHooks() public {
        IPostActionHook[] memory recs = new IPostActionHook[](11);
        for (uint256 i = 0; i < 11; i++) {
            recs[i] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));
        }

        vm.expectRevert(abi.encodeWithSelector(PostActionHookCombinator.TooManyHooks.selector, 11, 10));
        new PostActionHookCombinator(recs);
    }

    function test_PostActionHookCombinator_RevertsOnEmptyHooks() public {
        IPostActionHook[] memory recs = new IPostActionHook[](0);

        vm.expectRevert(PostActionHookCombinator.EmptyHooks.selector);
        new PostActionHookCombinator(recs);
    }

    function test_PostActionHookCombinator_MaxHooksConstant() public {
        IPostActionHook[] memory recs = new IPostActionHook[](1);
        recs[0] = IPostActionHook(address(new AuthorizationTimePostActionHook(address(escrow), bytes32(0))));

        PostActionHookCombinator combinator = new PostActionHookCombinator(recs);
        assertEq(combinator.MAX_POST_ACTION_HOOKS(), 10, "MAX_POST_ACTION_HOOKS should be 10");
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
