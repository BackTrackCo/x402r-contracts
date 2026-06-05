// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployX402r} from "../../script/DeployX402r.s.sol";

/// @notice Exposes `DeployX402r`'s internal canonical pins so the test asserts against the SAME
///         constants the deploy script guards on — no mirrored copies in the test that could
///         silently drift from the script.
contract DeployConstants is DeployX402r {
    function escrow() external pure returns (address) {
        return BASE_AUTH_CAPTURE_ESCROW;
    }

    function escrowCodehash() external pure returns (bytes32) {
        return EXPECTED_ESCROW_CODEHASH;
    }

    function protocolFeeConfig() external pure returns (address) {
        return EXPECTED_PROTOCOL_FEE_CONFIG;
    }

    function paymentOperatorFactory() external pure returns (address) {
        return EXPECTED_PAYMENT_OPERATOR_FACTORY;
    }

    function escrowPeriodFactory() external pure returns (address) {
        return EXPECTED_ESCROW_PERIOD_FACTORY;
    }

    function freezeFactory() external pure returns (address) {
        return EXPECTED_FREEZE_FACTORY;
    }

    function refundRequestFactory() external pure returns (address) {
        return EXPECTED_REFUND_REQUEST_FACTORY;
    }

    function receiverRefundCollector() external pure returns (address) {
        return EXPECTED_RECEIVER_REFUND_COLLECTOR;
    }

    function paymentIndexRecorderHook() external pure returns (address) {
        return EXPECTED_PAYMENT_INDEX_RECORDER_HOOK;
    }
}

/// @title  CanonicalAddressesTest
/// @notice Cross-check for `deployments/canonical-v1.0.1.json` along two platform-independent axes:
///
///         1. Consistency — every address in the manifest equals the corresponding `EXPECTED_*` pin
///            the deploy script guards on. This binds the manifest JSON to the single source of
///            truth (`DeployX402r`) so the two cannot silently diverge (e.g. someone edits one copy
///            and not the other).
///
///         2. On-chain reality — each canonical address is live on Base, and the escrow matches its
///            pinned codehash. This binds the *listed* address to what is actually deployed, which is
///            the guarantee that matters. Gated on `BASE_RPC_URL` so it skips cleanly off-network.
///
///         Note on why this does NOT re-derive addresses from `creationCode`: CREATE2 addresses are a
///         function of the exact init bytecode, and Solc's `via_ir` output for the heaviest contract
///         (`PaymentOperatorFactory`) is not byte-identical across platform builds of the same
///         compiler version (macOS vs Linux). A local-recompute assertion therefore produces a
///         false-positive "drift" on any platform other than the one the canonical deploy was
///         produced on. The deploy script's own `_assertCanonicalPin` still recomputes at deploy time
///         (on the deploy platform, where it is the correct check); here we verify against the
///         manifest and against on-chain reality instead, both of which are platform-invariant.
contract CanonicalAddressesTest is Test {
    string internal constant MANIFEST = "deployments/canonical-v1.0.1.json";
    string internal constant MANIFEST_V1_0_2 = "deployments/canonical-v1.0.2.json";

    DeployConstants internal pins;

    function setUp() public {
        pins = new DeployConstants();
    }

    // --------------------------------------------------------------------------------------------
    // 1. Consistency: manifest JSON == deploy-script pins (pure, platform/version invariant)
    // --------------------------------------------------------------------------------------------

    function test_ManifestEscrowMatchesScript() public view {
        assertEq(
            _json(MANIFEST, ".escrow"), pins.escrow(), "v1.0.1 manifest escrow != DeployX402r.BASE_AUTH_CAPTURE_ESCROW"
        );
        assertEq(
            _json(MANIFEST_V1_0_2, ".escrow"),
            pins.escrow(),
            "v1.0.2 manifest escrow != DeployX402r.BASE_AUTH_CAPTURE_ESCROW"
        );
    }

    function test_ManifestContractsMatchScriptPins() public view {
        // PaymentOperatorFactory lives in the v1.0.2 manifest (source changed; see canonical-v1.0.2.json).
        assertEq(
            _json(MANIFEST_V1_0_2, ".contracts.PaymentOperatorFactory"),
            pins.paymentOperatorFactory(),
            "PaymentOperatorFactory"
        );
        assertEq(_json(MANIFEST, ".contracts.EscrowPeriodFactory"), pins.escrowPeriodFactory(), "EscrowPeriodFactory");
        assertEq(_json(MANIFEST, ".contracts.FreezeFactory"), pins.freezeFactory(), "FreezeFactory");
        assertEq(
            _json(MANIFEST, ".contracts.RefundRequestFactory"), pins.refundRequestFactory(), "RefundRequestFactory"
        );
        assertEq(
            _json(MANIFEST, ".contracts.ReceiverRefundCollector"),
            pins.receiverRefundCollector(),
            "ReceiverRefundCollector"
        );
        assertEq(
            _json(MANIFEST, ".contracts.PaymentIndexRecorderHook"),
            pins.paymentIndexRecorderHook(),
            "PaymentIndexRecorderHook"
        );
    }

    // --------------------------------------------------------------------------------------------
    // 2. On-chain reality: canonical addresses are live on Base (fork, gated on BASE_RPC_URL)
    // --------------------------------------------------------------------------------------------

    function test_CanonicalContractsLiveOnBase() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }

        // Read every pin off the harness BEFORE forking: the harness is deployed on the local state
        // in setUp(), so it does not exist on the Base fork. Cache to memory, then switch state.
        address escrowAddr = pins.escrow();
        bytes32 expectedEscrowCodehash = pins.escrowCodehash();
        address[7] memory canonical = [
            pins.protocolFeeConfig(),
            pins.paymentOperatorFactory(),
            pins.escrowPeriodFactory(),
            pins.freezeFactory(),
            pins.refundRequestFactory(),
            pins.receiverRefundCollector(),
            pins.paymentIndexRecorderHook()
        ];
        string[7] memory names = [
            "ProtocolFeeConfig",
            "PaymentOperatorFactory",
            "EscrowPeriodFactory",
            "FreezeFactory",
            "RefundRequestFactory",
            "ReceiverRefundCollector",
            "PaymentIndexRecorderHook"
        ];

        vm.createSelectFork(rpc);

        assertEq(escrowAddr.codehash, expectedEscrowCodehash, "escrow codehash on Base != EXPECTED_ESCROW_CODEHASH");
        for (uint256 i = 0; i < canonical.length; i++) {
            assertGt(
                canonical[i].code.length,
                0,
                string.concat(names[i], " has no code on Base - manifest address is not live")
            );
        }
    }

    function _json(string memory manifest, string memory key) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(manifest), key);
    }
}
