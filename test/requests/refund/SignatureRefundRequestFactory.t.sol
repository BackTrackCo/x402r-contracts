// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignatureRefundRequestFactory} from "../../../src/requests/refund/SignatureRefundRequestFactory.sol";
import {SignatureRefundRequest} from "../../../src/requests/refund/SignatureRefundRequest.sol";
import {SignatureCondition} from "../../../src/plugins/conditions/access/signature/SignatureCondition.sol";

contract SignatureRefundRequestFactoryTest is Test {
    SignatureRefundRequestFactory public factory;

    SignatureCondition public condition1;
    SignatureCondition public condition2;

    function setUp() public {
        factory = new SignatureRefundRequestFactory();
        condition1 = new SignatureCondition(makeAddr("signer1"));
        condition2 = new SignatureCondition(makeAddr("signer2"));
    }

    function test_deploy_deterministic() public {
        address predicted = factory.computeAddress(address(condition1));

        address deployed = factory.deploy(address(condition1));

        assertEq(deployed, predicted);
        assertEq(address(SignatureRefundRequest(deployed).SIGNATURE_CONDITION()), address(condition1));
    }

    function test_deploy_idempotent() public {
        address first = factory.deploy(address(condition1));
        address second = factory.deploy(address(condition1));

        assertEq(first, second);
    }

    function test_deploy_differentConditions() public {
        address rr1 = factory.deploy(address(condition1));
        address rr2 = factory.deploy(address(condition2));

        assertTrue(rr1 != rr2);
        assertEq(address(SignatureRefundRequest(rr1).SIGNATURE_CONDITION()), address(condition1));
        assertEq(address(SignatureRefundRequest(rr2).SIGNATURE_CONDITION()), address(condition2));
    }

    function test_deploy_zeroCondition() public {
        vm.expectRevert(SignatureRefundRequestFactory.ZeroCondition.selector);
        factory.deploy(address(0));
    }

    function test_getDeployed_returnsZeroBeforeDeploy() public view {
        assertEq(factory.getDeployed(address(condition1)), address(0));
    }

    function test_getDeployed_returnsAddressAfterDeploy() public {
        address deployed = factory.deploy(address(condition1));
        assertEq(factory.getDeployed(address(condition1)), deployed);
    }

    function test_deploy_emitsEvent() public {
        address predicted = factory.computeAddress(address(condition1));

        vm.expectEmit(true, true, false, false);
        emit SignatureRefundRequestFactory.SignatureRefundRequestDeployed(predicted, address(condition1));

        factory.deploy(address(condition1));
    }
}
