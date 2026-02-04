// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArbiterRegistry} from "../src/registry/ArbiterRegistry.sol";
import {AlreadyRegistered, NotRegistered, EmptyUri} from "../src/registry/types/Errors.sol";
import {ArbiterRegistered, ArbiterUriUpdated, ArbiterDeregistered} from "../src/registry/types/Events.sol";

contract ArbiterRegistryTest is Test {
    ArbiterRegistry public registry;

    address public arbiter1;
    address public arbiter2;
    address public arbiter3;

    string constant URI_1 = "https://arbiter1.example.com/api/disputes";
    string constant URI_2 = "ipfs://QmXxx1234567890abcdef";
    string constant URI_3 = "https://arbiter3.example.com/disputes";
    string constant UPDATED_URI = "https://arbiter1-updated.example.com/api";

    function setUp() public {
        registry = new ArbiterRegistry();
        arbiter1 = makeAddr("arbiter1");
        arbiter2 = makeAddr("arbiter2");
        arbiter3 = makeAddr("arbiter3");
    }

    // ============ register() Tests ============

    function test_register_success() public {
        vm.prank(arbiter1);
        vm.expectEmit(true, false, false, true);
        emit ArbiterRegistered(arbiter1, URI_1);
        registry.register(URI_1);

        assertTrue(registry.isRegistered(arbiter1));
        assertEq(registry.getUri(arbiter1), URI_1);
        assertEq(registry.arbiterCount(), 1);
    }

    function test_register_multipleArbiters() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        vm.prank(arbiter2);
        registry.register(URI_2);

        vm.prank(arbiter3);
        registry.register(URI_3);

        assertTrue(registry.isRegistered(arbiter1));
        assertTrue(registry.isRegistered(arbiter2));
        assertTrue(registry.isRegistered(arbiter3));
        assertEq(registry.arbiterCount(), 3);
    }

    function test_register_revertIfAlreadyRegistered() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        vm.prank(arbiter1);
        vm.expectRevert(AlreadyRegistered.selector);
        registry.register(URI_2);
    }

    function test_register_revertIfEmptyUri() public {
        vm.prank(arbiter1);
        vm.expectRevert(EmptyUri.selector);
        registry.register("");
    }

    // ============ updateUri() Tests ============

    function test_updateUri_success() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        vm.prank(arbiter1);
        vm.expectEmit(true, false, false, true);
        emit ArbiterUriUpdated(arbiter1, URI_1, UPDATED_URI);
        registry.updateUri(UPDATED_URI);

        assertEq(registry.getUri(arbiter1), UPDATED_URI);
    }

    function test_updateUri_revertIfNotRegistered() public {
        vm.prank(arbiter1);
        vm.expectRevert(NotRegistered.selector);
        registry.updateUri(UPDATED_URI);
    }

    function test_updateUri_revertIfEmptyUri() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        vm.prank(arbiter1);
        vm.expectRevert(EmptyUri.selector);
        registry.updateUri("");
    }

    // ============ deregister() Tests ============

    function test_deregister_success() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        assertTrue(registry.isRegistered(arbiter1));

        vm.prank(arbiter1);
        vm.expectEmit(true, false, false, false);
        emit ArbiterDeregistered(arbiter1);
        registry.deregister();

        assertFalse(registry.isRegistered(arbiter1));
        assertEq(registry.getUri(arbiter1), "");
        assertEq(registry.arbiterCount(), 0);
    }

    function test_deregister_middleElement() public {
        // Register 3 arbiters
        vm.prank(arbiter1);
        registry.register(URI_1);
        vm.prank(arbiter2);
        registry.register(URI_2);
        vm.prank(arbiter3);
        registry.register(URI_3);

        assertEq(registry.arbiterCount(), 3);

        // Deregister the middle one
        vm.prank(arbiter2);
        registry.deregister();

        // Check state
        assertEq(registry.arbiterCount(), 2);
        assertTrue(registry.isRegistered(arbiter1));
        assertFalse(registry.isRegistered(arbiter2));
        assertTrue(registry.isRegistered(arbiter3));

        // Verify we can still enumerate and find both remaining arbiters
        (address[] memory arbiters,,) = registry.getArbiters(0, 10);
        assertEq(arbiters.length, 2);

        // Both arbiter1 and arbiter3 should be in the list
        bool found1 = false;
        bool found3 = false;
        for (uint256 i = 0; i < arbiters.length; i++) {
            if (arbiters[i] == arbiter1) found1 = true;
            if (arbiters[i] == arbiter3) found3 = true;
        }
        assertTrue(found1, "arbiter1 should still be registered");
        assertTrue(found3, "arbiter3 should still be registered");
    }

    function test_deregister_revertIfNotRegistered() public {
        vm.prank(arbiter1);
        vm.expectRevert(NotRegistered.selector);
        registry.deregister();
    }

    function test_deregister_canReRegister() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        vm.prank(arbiter1);
        registry.deregister();

        // Should be able to register again
        vm.prank(arbiter1);
        registry.register(UPDATED_URI);

        assertTrue(registry.isRegistered(arbiter1));
        assertEq(registry.getUri(arbiter1), UPDATED_URI);
    }

    // ============ View Function Tests ============

    function test_getUri_returnsEmptyForUnregistered() public view {
        assertEq(registry.getUri(arbiter1), "");
    }

    function test_isRegistered_returnsFalseForUnregistered() public view {
        assertFalse(registry.isRegistered(arbiter1));
    }

    function test_arbiterCount_initiallyZero() public view {
        assertEq(registry.arbiterCount(), 0);
    }

    function test_getArbiters_emptyRegistry() public view {
        (address[] memory arbiters, string[] memory uris, uint256 total) = registry.getArbiters(0, 10);
        assertEq(arbiters.length, 0);
        assertEq(uris.length, 0);
        assertEq(total, 0);
    }

    function test_getArbiters_pagination() public {
        // Register 3 arbiters
        vm.prank(arbiter1);
        registry.register(URI_1);
        vm.prank(arbiter2);
        registry.register(URI_2);
        vm.prank(arbiter3);
        registry.register(URI_3);

        // Get first 2
        (address[] memory arbiters, string[] memory uris, uint256 total) = registry.getArbiters(0, 2);
        assertEq(arbiters.length, 2);
        assertEq(uris.length, 2);
        assertEq(total, 3);
        assertEq(arbiters[0], arbiter1);
        assertEq(arbiters[1], arbiter2);
        assertEq(uris[0], URI_1);
        assertEq(uris[1], URI_2);

        // Get last 1 with offset
        (arbiters, uris, total) = registry.getArbiters(2, 10);
        assertEq(arbiters.length, 1);
        assertEq(uris.length, 1);
        assertEq(total, 3);
        assertEq(arbiters[0], arbiter3);
        assertEq(uris[0], URI_3);
    }

    function test_getArbiters_offsetBeyondTotal() public {
        vm.prank(arbiter1);
        registry.register(URI_1);

        (address[] memory arbiters, string[] memory uris, uint256 total) = registry.getArbiters(10, 10);
        assertEq(arbiters.length, 0);
        assertEq(uris.length, 0);
        assertEq(total, 1);
    }

    function test_getArbiters_countExceedsRemaining() public {
        vm.prank(arbiter1);
        registry.register(URI_1);
        vm.prank(arbiter2);
        registry.register(URI_2);

        // Request 100 but only 2 exist
        (address[] memory arbiters,, uint256 total) = registry.getArbiters(0, 100);
        assertEq(arbiters.length, 2);
        assertEq(total, 2);
    }

    // ============ Fuzz Tests ============

    function testFuzz_register_anyUri(string calldata uri) public {
        vm.assume(bytes(uri).length > 0);

        vm.prank(arbiter1);
        registry.register(uri);

        assertTrue(registry.isRegistered(arbiter1));
        assertEq(registry.getUri(arbiter1), uri);
    }

    function testFuzz_pagination_bounds(uint256 offset, uint256 count) public {
        // Register some arbiters
        vm.prank(arbiter1);
        registry.register(URI_1);
        vm.prank(arbiter2);
        registry.register(URI_2);

        // Bound count to reasonable value
        count = bound(count, 0, 100);

        // This should never revert
        (address[] memory arbiters,, uint256 total) = registry.getArbiters(offset, count);
        assertEq(total, 2);

        // Result length should never exceed count or total
        assertTrue(arbiters.length <= count);
        assertTrue(arbiters.length <= total);
    }
}
