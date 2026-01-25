// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ICondition} from "../src/commerce-payments/conditions/ICondition.sol";
import {AndCondition} from "../src/commerce-payments/conditions/combinators/AndCondition.sol";
import {OrCondition} from "../src/commerce-payments/conditions/combinators/OrCondition.sol";
import {AlwaysTrueCondition} from "../src/commerce-payments/conditions/access/AlwaysTrueCondition.sol";

/**
 * @title CombinatorLimitsTest
 * @notice Tests for condition combinator array length limits
 * @dev Ensures MAX_CONDITIONS (10) is enforced to prevent gas griefing
 */
contract CombinatorLimitsTest is Test {
    AlwaysTrueCondition public alwaysTrue;

    function setUp() public {
        alwaysTrue = new AlwaysTrueCondition();
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
}
