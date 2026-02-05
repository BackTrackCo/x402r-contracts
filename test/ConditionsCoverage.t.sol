// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Conditions
import {ICondition} from "../src/plugins/conditions/ICondition.sol";
import {IRecorder} from "../src/plugins/recorders/IRecorder.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {NotCondition} from "../src/plugins/conditions/combinators/NotCondition.sol";
import {RecorderCombinator} from "../src/plugins/recorders/combinators/RecorderCombinator.sol";
import {StaticAddressCondition} from "../src/plugins/conditions/access/static-address/StaticAddressCondition.sol";
import {
    StaticAddressConditionFactory
} from "../src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol";

/// @notice Mock recorder for testing RecorderCombinator
contract MockRecorder is IRecorder {
    uint256 public recordCount;
    AuthCaptureEscrow.PaymentInfo public lastPaymentInfo;

    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address) external {
        recordCount++;
        lastPaymentInfo = paymentInfo;
    }
}

/// @notice Mock condition that can be toggled
contract MockCondition is ICondition {
    bool public result = true;

    function setResult(bool _result) external {
        result = _result;
    }

    function check(AuthCaptureEscrow.PaymentInfo calldata, uint256, address) external view returns (bool) {
        return result;
    }
}

contract ConditionsCoverageTest is Test {
    AlwaysTrueCondition public alwaysTrue;
    ReceiverCondition public receiverCondition;
    PayerCondition public payerCondition;
    MockCondition public mockCondition;

    address public payer = makeAddr("payer");
    address public receiver = makeAddr("receiver");
    address public operator = makeAddr("operator");

    function setUp() public {
        alwaysTrue = new AlwaysTrueCondition();
        receiverCondition = new ReceiverCondition();
        payerCondition = new PayerCondition();
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

    // ============ AlwaysTrueCondition Tests ============

    function test_AlwaysTrueCondition_ReturnsTrue() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(alwaysTrue.check(paymentInfo, 100, payer));
        assertTrue(alwaysTrue.check(paymentInfo, 0, address(0)));
    }

    // ============ ReceiverCondition Tests ============

    function test_ReceiverCondition_AllowsReceiver() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(receiverCondition.check(paymentInfo, 100, receiver));
    }

    function test_ReceiverCondition_DeniesNonReceiver() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertFalse(receiverCondition.check(paymentInfo, 100, payer));
        assertFalse(receiverCondition.check(paymentInfo, 100, operator));
    }

    // ============ NotCondition Tests ============

    function test_NotCondition_NegatesTrue() public {
        mockCondition.setResult(true);
        NotCondition notCondition = new NotCondition(ICondition(address(mockCondition)));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertFalse(notCondition.check(paymentInfo, 100, payer));
    }

    function test_NotCondition_NegatesFalse() public {
        mockCondition.setResult(false);
        NotCondition notCondition = new NotCondition(ICondition(address(mockCondition)));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(notCondition.check(paymentInfo, 100, payer));
    }

    function test_NotCondition_RevertsOnZeroAddress() public {
        vm.expectRevert(NotCondition.ZeroCondition.selector);
        new NotCondition(ICondition(address(0)));
    }

    function test_NotCondition_ReturnsCondition() public {
        NotCondition notCondition = new NotCondition(ICondition(address(mockCondition)));
        assertEq(address(notCondition.CONDITION()), address(mockCondition));
    }

    // ============ RecorderCombinator Tests ============

    function test_RecorderCombinator_CallsAllRecorders() public {
        MockRecorder recorder1 = new MockRecorder();
        MockRecorder recorder2 = new MockRecorder();

        IRecorder[] memory recorders = new IRecorder[](2);
        recorders[0] = recorder1;
        recorders[1] = recorder2;

        RecorderCombinator combinator = new RecorderCombinator(recorders);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        vm.prank(operator);
        combinator.record(paymentInfo, 500, payer);

        assertEq(recorder1.recordCount(), 1);
        assertEq(recorder2.recordCount(), 1);
    }

    function test_RecorderCombinator_RevertsOnEmptyRecorders() public {
        IRecorder[] memory recorders = new IRecorder[](0);

        vm.expectRevert(RecorderCombinator.EmptyRecorders.selector);
        new RecorderCombinator(recorders);
    }

    function test_RecorderCombinator_RevertsOnTooManyRecorders() public {
        IRecorder[] memory recorders = new IRecorder[](11);
        for (uint256 i = 0; i < 11; i++) {
            recorders[i] = new MockRecorder();
        }

        vm.expectRevert(abi.encodeWithSelector(RecorderCombinator.TooManyRecorders.selector, 11, 10));
        new RecorderCombinator(recorders);
    }

    function test_RecorderCombinator_RevertsOnZeroRecorder() public {
        IRecorder[] memory recorders = new IRecorder[](2);
        recorders[0] = new MockRecorder();
        recorders[1] = IRecorder(address(0));

        vm.expectRevert(abi.encodeWithSelector(RecorderCombinator.ZeroRecorder.selector, 1));
        new RecorderCombinator(recorders);
    }

    function test_RecorderCombinator_GetRecorders() public {
        MockRecorder recorder1 = new MockRecorder();
        MockRecorder recorder2 = new MockRecorder();

        IRecorder[] memory recorders = new IRecorder[](2);
        recorders[0] = recorder1;
        recorders[1] = recorder2;

        RecorderCombinator combinator = new RecorderCombinator(recorders);

        IRecorder[] memory result = combinator.getRecorders();
        assertEq(result.length, 2);
        assertEq(address(result[0]), address(recorder1));
        assertEq(address(result[1]), address(recorder2));
    }

    function test_RecorderCombinator_GetRecorderCount() public {
        MockRecorder recorder1 = new MockRecorder();

        IRecorder[] memory recorders = new IRecorder[](1);
        recorders[0] = recorder1;

        RecorderCombinator combinator = new RecorderCombinator(recorders);
        assertEq(combinator.getRecorderCount(), 1);
    }

    function test_RecorderCombinator_AccessRecordersByIndex() public {
        MockRecorder recorder1 = new MockRecorder();
        MockRecorder recorder2 = new MockRecorder();

        IRecorder[] memory recorders = new IRecorder[](2);
        recorders[0] = recorder1;
        recorders[1] = recorder2;

        RecorderCombinator combinator = new RecorderCombinator(recorders);

        assertEq(address(combinator.recorders(0)), address(recorder1));
        assertEq(address(combinator.recorders(1)), address(recorder2));
    }

    // ============ StaticAddressConditionFactory Tests ============

    function test_StaticAddressConditionFactory_Deploy() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter = makeAddr("arbiter");

        address condition = factory.deploy(arbiter);

        assertTrue(condition != address(0));
        assertEq(factory.getDeployed(arbiter), condition);
    }

    function test_StaticAddressConditionFactory_DeployReturnsSameAddress() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter = makeAddr("arbiter");

        address condition1 = factory.deploy(arbiter);
        address condition2 = factory.deploy(arbiter);

        assertEq(condition1, condition2);
    }

    function test_StaticAddressConditionFactory_ComputeAddress() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter = makeAddr("arbiter");

        address computed = factory.computeAddress(arbiter);
        address deployed = factory.deploy(arbiter);

        assertEq(computed, deployed);
    }

    function test_StaticAddressConditionFactory_GetKey() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter1 = makeAddr("arbiter1");
        address arbiter2 = makeAddr("arbiter2");

        bytes32 key1 = factory.getKey(arbiter1);
        bytes32 key2 = factory.getKey(arbiter2);

        assertTrue(key1 != key2);
    }

    function test_StaticAddressConditionFactory_DifferentAddresses() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter1 = makeAddr("arbiter1");
        address arbiter2 = makeAddr("arbiter2");

        address condition1 = factory.deploy(arbiter1);
        address condition2 = factory.deploy(arbiter2);

        assertTrue(condition1 != condition2);
    }

    function test_StaticAddressConditionFactory_RevertsOnZeroAddress() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();

        vm.expectRevert(StaticAddressConditionFactory.ZeroAddress.selector);
        factory.deploy(address(0));
    }

    function test_StaticAddressConditionFactory_DeployedConditionWorks() public {
        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        address arbiter = makeAddr("arbiter");

        address conditionAddr = factory.deploy(arbiter);
        StaticAddressCondition condition = StaticAddressCondition(conditionAddr);

        assertEq(condition.DESIGNATED_ADDRESS(), arbiter);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        assertTrue(condition.check(paymentInfo, 100, arbiter));
        assertFalse(condition.check(paymentInfo, 100, payer));
    }
}
