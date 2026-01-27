// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Conditions
import {ICondition} from "../src/conditions/ICondition.sol";
import {IRecorder} from "../src/conditions/IRecorder.sol";
import {AlwaysTrueCondition} from "../src/conditions/access/AlwaysTrueCondition.sol";
import {ReceiverCondition} from "../src/conditions/access/ReceiverCondition.sol";
import {PayerCondition} from "../src/conditions/access/PayerCondition.sol";
import {NotCondition} from "../src/conditions/combinators/NotCondition.sol";
import {RecorderCombinator} from "../src/conditions/combinators/RecorderCombinator.sol";
import {FreezePolicyFactory} from "../src/conditions/escrow-period/freeze-policy/FreezePolicyFactory.sol";
import {FreezePolicy} from "../src/conditions/escrow-period/freeze-policy/FreezePolicy.sol";

/// @notice Mock recorder for testing RecorderCombinator
contract MockRecorder is IRecorder {
    uint256 public recordCount;
    AuthCaptureEscrow.PaymentInfo public lastPaymentInfo;
    uint256 public lastAmount;
    address public lastCaller;

    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller) external {
        recordCount++;
        lastPaymentInfo = paymentInfo;
        lastAmount = amount;
        lastCaller = caller;
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
        combinator.record(paymentInfo, 500, payer);

        assertEq(recorder1.recordCount(), 1);
        assertEq(recorder2.recordCount(), 1);
        assertEq(recorder1.lastAmount(), 500);
        assertEq(recorder2.lastCaller(), payer);
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

    // ============ FreezePolicyFactory Tests ============

    function test_FreezePolicyFactory_Deploy() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        address policy = factory.deploy(address(payerCondition), address(payerCondition), 3 days);

        assertTrue(policy != address(0));
        assertEq(factory.getDeployed(address(payerCondition), address(payerCondition), 3 days), policy);
    }

    function test_FreezePolicyFactory_DeployReturnsSameAddress() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        address policy1 = factory.deploy(address(payerCondition), address(payerCondition), 3 days);
        address policy2 = factory.deploy(address(payerCondition), address(payerCondition), 3 days);

        assertEq(policy1, policy2);
    }

    function test_FreezePolicyFactory_ComputeAddress() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        address computed = factory.computeAddress(address(payerCondition), address(payerCondition), 3 days);
        address deployed = factory.deploy(address(payerCondition), address(payerCondition), 3 days);

        assertEq(computed, deployed);
    }

    function test_FreezePolicyFactory_GetKey() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        bytes32 key1 = factory.getKey(address(payerCondition), address(payerCondition), 3 days);
        bytes32 key2 = factory.getKey(address(payerCondition), address(receiverCondition), 3 days);

        assertTrue(key1 != key2);
    }

    function test_FreezePolicyFactory_DifferentConfigs() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        address policy1 = factory.deploy(address(payerCondition), address(payerCondition), 3 days);
        address policy2 = factory.deploy(address(payerCondition), address(receiverCondition), 7 days);

        assertTrue(policy1 != policy2);
    }

    function test_FreezePolicyFactory_DeployedPolicyWorks() public {
        FreezePolicyFactory factory = new FreezePolicyFactory();

        address policyAddr = factory.deploy(address(payerCondition), address(payerCondition), 3 days);
        FreezePolicy policy = FreezePolicy(policyAddr);

        assertEq(address(policy.FREEZE_CONDITION()), address(payerCondition));
        assertEq(address(policy.UNFREEZE_CONDITION()), address(payerCondition));
        assertEq(policy.FREEZE_DURATION(), 3 days);
    }
}
