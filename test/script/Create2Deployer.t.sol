// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Create2Deployer, ICreateX} from "../../script/deploy/Create2Deployer.sol";

// Trivial init code: minimal "deploy" prelude that copies a single STOP opcode (0x00) at
// position 12 into memory[0] and returns it as runtime. Total length: 13 bytes.
//   PUSH1 0x01   (size)
//   PUSH1 0x0C   (src offset = 12, where the runtime byte lives in code)
//   PUSH1 0x00   (dest offset)
//   CODECOPY
//   PUSH1 0x01   (return size)
//   PUSH1 0x00   (return offset)
//   RETURN
//   0x00         (runtime: STOP)
bytes constant TRIVIAL_INIT_CODE = hex"6001600C60003960016000F300";

/// @notice Test harness that exposes Create2Deployer's internal helpers as external functions.
contract Create2DeployerHarness is Create2Deployer {
    function deploy2(string memory label, bytes memory initCode) external returns (address) {
        return _deploy2(label, initCode);
    }

    function predict2(string memory label, bytes32 initCodeHash) external pure returns (address) {
        return _predict2(label, initCodeHash);
    }
}

/// @title  Create2DeployerTest
/// @notice Covers the idempotency branch added in PR #36: re-running `_deploy2` on a chain where
///         the predicted address already has code must skip the CreateX call (which would
///         otherwise revert), and must return the same address as the first call.
contract Create2DeployerTest is Test {
    Create2DeployerHarness internal harness;
    address internal constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function setUp() public {
        // CreateX isn't deployed in a fresh foundry chain; etch the bytecode of a forwarder that
        // mimics `deployCreate2(salt, initCode) -> address` for the duration of the test.
        // Easier: deploy a minimal mock that performs the CREATE2 ourselves.
        vm.etch(CREATEX, type(MockCreateX).runtimeCode);
        harness = new Create2DeployerHarness();
    }

    function test_FirstCallDeploys() public {
        address predicted = harness.predict2("test::trivial", keccak256(TRIVIAL_INIT_CODE));
        assertEq(predicted.code.length, 0, "address should be empty before deploy");

        address deployed = harness.deploy2("test::trivial", TRIVIAL_INIT_CODE);

        assertEq(deployed, predicted, "deployed address must match prediction");
        assertGt(deployed.code.length, 0, "deployed address must have code");
    }

    function test_SecondCallSkips() public {
        address first = harness.deploy2("test::trivial", TRIVIAL_INIT_CODE);

        // Sentinel: expect no calls to CreateX on the second invocation. Replace CreateX with
        // a contract that reverts on any call — if `_deploy2` reaches CreateX, the test fails.
        vm.etch(CREATEX, type(RevertingCreateX).runtimeCode);

        address second = harness.deploy2("test::trivial", TRIVIAL_INIT_CODE);

        assertEq(second, first, "idempotent re-run must return the same address without re-calling CreateX");
    }

    function test_VmEtchedCodeAtPredictedAddressShortCircuits() public {
        // Simulates a chain where the canonical address already has code (e.g., partial broadcast
        // resumed from a different deploy script). `_deploy2` should not call CreateX at all.
        address predicted = harness.predict2("test::pre-etched", keccak256(TRIVIAL_INIT_CODE));
        vm.etch(predicted, hex"00");

        // Sentinel: any call to CreateX must revert.
        vm.etch(CREATEX, type(RevertingCreateX).runtimeCode);

        address deployed = harness.deploy2("test::pre-etched", TRIVIAL_INIT_CODE);
        assertEq(deployed, predicted, "must short-circuit to the pre-existing predicted address");
    }
}

/// @notice Mock replacement for CreateX: performs a vanilla CREATE2 (no permissionless-salt-guard
///         hashing) so we can drive predicted addresses with the same `keccak256(0xff || addr ||
///         keccak256(salt) || initCodeHash)` derivation that `_predict2` uses.
contract MockCreateX is ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address deployed) {
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        assembly {
            deployed := create2(callvalue(), add(initCode, 0x20), mload(initCode), guardedSalt)
        }
        require(deployed != address(0), "MockCreateX: deploy failed");
    }
}

/// @notice Sentinel CreateX that always reverts — used to assert `_deploy2` never reaches CreateX
///         on the idempotent branches.
contract RevertingCreateX is ICreateX {
    function deployCreate2(bytes32, bytes memory) external payable returns (address) {
        revert("RevertingCreateX: idempotency branch must not call CreateX");
    }
}
