// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    SignatureConditionFactory
} from "../../../../../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";
import {SignatureCondition} from "../../../../../src/plugins/conditions/access/signature/SignatureCondition.sol";

contract SignatureConditionFactoryTest is Test {
    SignatureConditionFactory public factory;

    address public signer1;
    address public signer2;

    function setUp() public {
        factory = new SignatureConditionFactory();
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
    }

    function test_deploy_deterministic() public {
        // Compute address before deployment
        address predicted = factory.computeAddress(signer1);

        // Deploy
        address deployed = factory.deploy(signer1);

        // Should match predicted address
        assertEq(deployed, predicted);

        // Deployed condition should have correct signer
        assertEq(SignatureCondition(deployed).SIGNER(), signer1);
    }

    function test_deploy_idempotent() public {
        address first = factory.deploy(signer1);
        address second = factory.deploy(signer1);

        // Second deploy returns same address (no new deployment)
        assertEq(first, second);
    }

    function test_deploy_differentSigners() public {
        address cond1 = factory.deploy(signer1);
        address cond2 = factory.deploy(signer2);

        // Different signers produce different addresses
        assertTrue(cond1 != cond2);

        // Each has correct signer
        assertEq(SignatureCondition(cond1).SIGNER(), signer1);
        assertEq(SignatureCondition(cond2).SIGNER(), signer2);
    }

    function test_deploy_zeroSigner() public {
        vm.expectRevert(SignatureConditionFactory.ZeroSigner.selector);
        factory.deploy(address(0));
    }

    function test_getDeployed_returnsZeroBeforeDeploy() public view {
        assertEq(factory.getDeployed(signer1), address(0));
    }

    function test_getDeployed_returnsAddressAfterDeploy() public {
        address deployed = factory.deploy(signer1);
        assertEq(factory.getDeployed(signer1), deployed);
    }

    function test_deploy_emitsEvent() public {
        address predicted = factory.computeAddress(signer1);

        vm.expectEmit(true, true, false, false);
        emit SignatureConditionFactory.SignatureConditionDeployed(predicted, signer1);

        factory.deploy(signer1);
    }
}
