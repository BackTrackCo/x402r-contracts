// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Conditions
import {IPreActionCondition} from "../src/plugins/pre-action-conditions/IPreActionCondition.sol";
import {IPostActionHook} from "../src/plugins/post-action-hooks/IPostActionHook.sol";
import {
    AlwaysTruePreActionCondition
} from "../src/plugins/pre-action-conditions/access/AlwaysTruePreActionCondition.sol";
import {ReceiverPreActionCondition} from "../src/plugins/pre-action-conditions/access/ReceiverPreActionCondition.sol";
import {PayerPreActionCondition} from "../src/plugins/pre-action-conditions/access/PayerPreActionCondition.sol";
import {NotPreActionCondition} from "../src/plugins/pre-action-conditions/combinators/NotPreActionCondition.sol";
import {PostActionHookCombinator} from "../src/plugins/post-action-hooks/combinators/PostActionHookCombinator.sol";
import {
    StaticAddressPreActionCondition
} from "../src/plugins/pre-action-conditions/access/static-address/StaticAddressPreActionCondition.sol";
import {
    StaticAddressPreActionConditionFactory
} from "../src/plugins/pre-action-conditions/access/static-address/StaticAddressPreActionConditionFactory.sol";

/// @notice Mock hook for testing PostActionHookCombinator
contract MockPostActionHook is IPostActionHook {
    uint256 public recordCount;
    AuthCaptureEscrow.PaymentInfo public lastPaymentInfo;

    function run(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address, bytes calldata) external {
        recordCount++;
        lastPaymentInfo = paymentInfo;
    }
}

/// @notice Mock condition that can be toggled
contract MockCondition is IPreActionCondition {
    bool public result = true;

    function setResult(bool _result) external {
        result = _result;
    }

    function check(AuthCaptureEscrow.PaymentInfo calldata, uint256, address, bytes calldata)
        external
        view
        returns (bool)
    {
        return result;
    }
}

contract PreActionConditionsCoverageTest is Test {
    AlwaysTruePreActionCondition public alwaysTrue;
    ReceiverPreActionCondition public receiverCondition;
    PayerPreActionCondition public payerCondition;
    MockCondition public mockCondition;

    address public payer = makeAddr("payer");
    address public receiver = makeAddr("receiver");
    address public operator = makeAddr("operator");

    function setUp() public {
        alwaysTrue = new AlwaysTruePreActionCondition();
        receiverCondition = new ReceiverPreActionCondition();
        payerCondition = new PayerPreActionCondition();
        mockCondition = new MockCondition();
    }

    function _createPaymentInfo() internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: payer,
            receiver: receiver,
            token: address(0),
            maxAmount: 1000,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 100,
            feeReceiver: operator,
            salt: 12345
        });
    }

    // ============ AlwaysTruePreActionCondition Tests ============

    function test_AlwaysTruePreActionCondition_ReturnsTrue() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(alwaysTrue.check(paymentInfo, 100, payer, ""));
        assertTrue(alwaysTrue.check(paymentInfo, 0, address(0), ""));
    }

    // ============ ReceiverPreActionCondition Tests ============

    function test_ReceiverPreActionCondition_AllowsReceiver() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(receiverCondition.check(paymentInfo, 100, receiver, ""));
    }

    function test_ReceiverPreActionCondition_DeniesNonReceiver() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertFalse(receiverCondition.check(paymentInfo, 100, payer, ""));
        assertFalse(receiverCondition.check(paymentInfo, 100, operator, ""));
    }

    // ============ NotPreActionCondition Tests ============

    function test_NotPreActionCondition_NegatesTrue() public {
        mockCondition.setResult(true);
        NotPreActionCondition notCondition = new NotPreActionCondition(IPreActionCondition(address(mockCondition)));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertFalse(notCondition.check(paymentInfo, 100, payer, ""));
    }

    function test_NotPreActionCondition_NegatesFalse() public {
        mockCondition.setResult(false);
        NotPreActionCondition notCondition = new NotPreActionCondition(IPreActionCondition(address(mockCondition)));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(notCondition.check(paymentInfo, 100, payer, ""));
    }

    function test_NotPreActionCondition_RevertsOnZeroAddress() public {
        vm.expectRevert(NotPreActionCondition.ZeroCondition.selector);
        new NotPreActionCondition(IPreActionCondition(address(0)));
    }

    function test_NotPreActionCondition_ReturnsCondition() public {
        NotPreActionCondition notCondition = new NotPreActionCondition(IPreActionCondition(address(mockCondition)));
        assertEq(address(notCondition.CONDITION()), address(mockCondition));
    }

    // ============ PostActionHookCombinator Tests ============

    function test_PostActionHookCombinator_CallsAllHooks() public {
        MockPostActionHook hook1 = new MockPostActionHook();
        MockPostActionHook hook2 = new MockPostActionHook();

        IPostActionHook[] memory hooks = new IPostActionHook[](2);
        hooks[0] = hook1;
        hooks[1] = hook2;

        PostActionHookCombinator combinator = new PostActionHookCombinator(hooks);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        vm.prank(operator);
        combinator.run(paymentInfo, 500, payer, "");

        assertEq(hook1.recordCount(), 1);
        assertEq(hook2.recordCount(), 1);
    }

    function test_PostActionHookCombinator_RevertsOnEmptyHooks() public {
        IPostActionHook[] memory hooks = new IPostActionHook[](0);

        vm.expectRevert(PostActionHookCombinator.EmptyHooks.selector);
        new PostActionHookCombinator(hooks);
    }

    function test_PostActionHookCombinator_RevertsOnTooManyHooks() public {
        IPostActionHook[] memory hooks = new IPostActionHook[](11);
        for (uint256 i = 0; i < 11; i++) {
            hooks[i] = new MockPostActionHook();
        }

        vm.expectRevert(abi.encodeWithSelector(PostActionHookCombinator.TooManyHooks.selector, 11, 10));
        new PostActionHookCombinator(hooks);
    }

    function test_PostActionHookCombinator_RevertsOnZeroHook() public {
        IPostActionHook[] memory hooks = new IPostActionHook[](2);
        hooks[0] = new MockPostActionHook();
        hooks[1] = IPostActionHook(address(0));

        vm.expectRevert(abi.encodeWithSelector(PostActionHookCombinator.ZeroHook.selector, 1));
        new PostActionHookCombinator(hooks);
    }

    function test_PostActionHookCombinator_GetHooks() public {
        MockPostActionHook hook1 = new MockPostActionHook();
        MockPostActionHook hook2 = new MockPostActionHook();

        IPostActionHook[] memory hooks = new IPostActionHook[](2);
        hooks[0] = hook1;
        hooks[1] = hook2;

        PostActionHookCombinator combinator = new PostActionHookCombinator(hooks);

        IPostActionHook[] memory result = combinator.getHooks();
        assertEq(result.length, 2);
        assertEq(address(result[0]), address(hook1));
        assertEq(address(result[1]), address(hook2));
    }

    function test_PostActionHookCombinator_GetRecorderCount() public {
        MockPostActionHook hook1 = new MockPostActionHook();

        IPostActionHook[] memory hooks = new IPostActionHook[](1);
        hooks[0] = hook1;

        PostActionHookCombinator combinator = new PostActionHookCombinator(hooks);
        assertEq(combinator.getHookCount(), 1);
    }

    function test_PostActionHookCombinator_AccessHooksByIndex() public {
        MockPostActionHook hook1 = new MockPostActionHook();
        MockPostActionHook hook2 = new MockPostActionHook();

        IPostActionHook[] memory hooks = new IPostActionHook[](2);
        hooks[0] = hook1;
        hooks[1] = hook2;

        PostActionHookCombinator combinator = new PostActionHookCombinator(hooks);

        assertEq(address(combinator.hooks(0)), address(hook1));
        assertEq(address(combinator.hooks(1)), address(hook2));
    }

    // ============ StaticAddressPreActionConditionFactory Tests ============

    function test_StaticAddressPreActionConditionFactory_Deploy() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter = makeAddr("arbiter");

        address condition = factory.deploy(arbiter);

        assertTrue(condition != address(0));
        assertEq(factory.getDeployed(arbiter), condition);
    }

    function test_StaticAddressPreActionConditionFactory_DeployReturnsSameAddress() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter = makeAddr("arbiter");

        address condition1 = factory.deploy(arbiter);
        address condition2 = factory.deploy(arbiter);

        assertEq(condition1, condition2);
    }

    function test_StaticAddressPreActionConditionFactory_ComputeAddress() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter = makeAddr("arbiter");

        address computed = factory.computeAddress(arbiter);
        address deployed = factory.deploy(arbiter);

        assertEq(computed, deployed);
    }

    function test_StaticAddressPreActionConditionFactory_GetKey() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter1 = makeAddr("arbiter1");
        address arbiter2 = makeAddr("arbiter2");

        bytes32 key1 = factory.getKey(arbiter1);
        bytes32 key2 = factory.getKey(arbiter2);

        assertTrue(key1 != key2);
    }

    function test_StaticAddressPreActionConditionFactory_DifferentAddresses() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter1 = makeAddr("arbiter1");
        address arbiter2 = makeAddr("arbiter2");

        address condition1 = factory.deploy(arbiter1);
        address condition2 = factory.deploy(arbiter2);

        assertTrue(condition1 != condition2);
    }

    function test_StaticAddressPreActionConditionFactory_RevertsOnZeroAddress() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();

        vm.expectRevert(StaticAddressPreActionConditionFactory.ZeroAddress.selector);
        factory.deploy(address(0));
    }

    function test_StaticAddressPreActionConditionFactory_DeployedConditionWorks() public {
        StaticAddressPreActionConditionFactory factory = new StaticAddressPreActionConditionFactory();
        address arbiter = makeAddr("arbiter");

        address conditionAddr = factory.deploy(arbiter);
        StaticAddressPreActionCondition condition = StaticAddressPreActionCondition(conditionAddr);

        assertEq(condition.DESIGNATED_ADDRESS(), arbiter);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(condition.check(paymentInfo, 100, arbiter, ""));
        assertFalse(condition.check(paymentInfo, 100, payer, ""));
    }
}
