// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Create2Deployer} from "../../script/deploy/Create2Deployer.sol";

import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {EscrowPeriodFactory} from "../../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../../src/plugins/freeze/FreezeFactory.sol";
import {RefundRequestFactory} from "../../src/requests/refund/RefundRequestFactory.sol";
import {ReceiverRefundCollector} from "../../src/collectors/ReceiverRefundCollector.sol";
import {PaymentIndexRecorderHook} from "../../src/plugins/hooks/PaymentIndexRecorderHook.sol";
import {HookCombinator} from "../../src/plugins/hooks/combinators/HookCombinator.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";

/// @notice Exposes Create2Deployer's internal `_predict2` so the test can re-derive addresses.
contract PredictHarness is Create2Deployer {
    function predict2(string memory label, bytes32 initCodeHash) external pure returns (address) {
        return _predict2(label, initCodeHash);
    }
}

/// @title  CanonicalAddressesTest
/// @notice Machine cross-check for `deployments/canonical-v1.0.1.json`. Re-derives each of the six
///         escrow-dependent v1.0.1 addresses from salt + initCodeHash using the locked toolchain and
///         the canonical escrow ctor arg, then asserts equality with the address listed in the JSON.
///         Nothing else binds the *listed* address to the recomputation `DeployX402r` performs — the
///         tx hashes are on-chain-auditable but the JSON can otherwise silently drift from what the
///         deploy script produces. This test closes that gap and doubles as a toolchain-drift canary:
///         any change to `foundry.toml` or a contract's creationCode shifts a predicted address and
///         fails here before it can fragment a real deploy.
contract CanonicalAddressesTest is Test {
    /// @dev Mirror of `DeployX402r.BASE_AUTH_CAPTURE_ESCROW` — the canonical Base AuthCaptureEscrow.
    address internal constant BASE_AUTH_CAPTURE_ESCROW = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;

    /// @dev Mirror of `DeployX402r.EXPECTED_PROTOCOL_FEE_CONFIG`. The operator factory bakes this in
    ///      as its second ctor arg, so the recomputation needs it to land at the canonical address.
    address internal constant EXPECTED_PROTOCOL_FEE_CONFIG = 0xBe2d24614F339a1eB103A399F93AA2a39Ca815Bc;

    string internal constant MANIFEST = "deployments/canonical-v1.0.1.json";

    PredictHarness internal harness;

    function setUp() public {
        harness = new PredictHarness();
    }

    /// @notice The escrow ctor arg every v1.0.1 address derives from must match the JSON manifest.
    function test_ManifestEscrowMatchesConstant() public view {
        address manifestEscrow = vm.parseJsonAddress(_manifest(), ".escrow");
        assertEq(manifestEscrow, BASE_AUTH_CAPTURE_ESCROW, "manifest escrow drifted from the deploy-script constant");
    }

    function test_PaymentOperatorFactoryMatchesManifest() public view {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PaymentOperatorFactory).creationCode,
                abi.encode(BASE_AUTH_CAPTURE_ESCROW, EXPECTED_PROTOCOL_FEE_CONFIG)
            )
        );
        _assertMatches("x402r-canonical-v1.0.1::PaymentOperatorFactory", initCodeHash, "PaymentOperatorFactory");
    }

    function test_EscrowPeriodFactoryMatchesManifest() public view {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(BASE_AUTH_CAPTURE_ESCROW)));
        _assertMatches("x402r-canonical-v1.0.1::EscrowPeriodFactory", initCodeHash, "EscrowPeriodFactory");
    }

    function test_FreezeFactoryMatchesManifest() public view {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(BASE_AUTH_CAPTURE_ESCROW)));
        _assertMatches("x402r-canonical-v1.0.1::FreezeFactory", initCodeHash, "FreezeFactory");
    }

    function test_RefundRequestFactoryMatchesManifest() public view {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(BASE_AUTH_CAPTURE_ESCROW)));
        _assertMatches("x402r-canonical-v1.0.1::RefundRequestFactory", initCodeHash, "RefundRequestFactory");
    }

    function test_ReceiverRefundCollectorMatchesManifest() public view {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(BASE_AUTH_CAPTURE_ESCROW))
        );
        _assertMatches("x402r-canonical-v1.0.1::ReceiverRefundCollector", initCodeHash, "ReceiverRefundCollector");
    }

    function test_PaymentIndexRecorderHookMatchesManifest() public view {
        bytes32 hookCombinatorCodehash = keccak256(type(HookCombinator).runtimeCode);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PaymentIndexRecorderHook).creationCode,
                abi.encode(BASE_AUTH_CAPTURE_ESCROW, hookCombinatorCodehash)
            )
        );
        _assertMatches("x402r-canonical-v1.0.1::PaymentIndexRecorderHook", initCodeHash, "PaymentIndexRecorderHook");
    }

    /// @notice ProtocolFeeConfig is env-dependent (owner/recipient), so it is only re-derived when the
    ///         canonical env is present (e.g. in a deploy dry-run / CI with secrets). When set, it must
    ///         recompute to the same pin the deploy script guards on.
    function test_ProtocolFeeConfigMatchesPinWhenEnvSet() public view {
        address owner = vm.envOr("OWNER_ADDRESS", address(0));
        address feeRecipient = vm.envOr("PROTOCOL_FEE_RECIPIENT", address(0));
        if (owner == address(0) || feeRecipient == address(0)) return; // skip without canonical env

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(ProtocolFeeConfig).creationCode, abi.encode(address(0), feeRecipient, owner))
        );
        address predicted = harness.predict2("x402r-canonical-v1::ProtocolFeeConfig", initCodeHash);
        assertEq(
            predicted,
            EXPECTED_PROTOCOL_FEE_CONFIG,
            "ProtocolFeeConfig recomputed from env does not match the canonical pin - env or toolchain drift"
        );
    }

    /// @dev Predict `label`'s address and assert it equals `.contracts.<contractKey>` in the manifest.
    function _assertMatches(string memory label, bytes32 initCodeHash, string memory contractKey) internal view {
        address predicted = harness.predict2(label, initCodeHash);
        address listed = vm.parseJsonAddress(_manifest(), string.concat(".contracts.", contractKey));
        assertEq(
            predicted, listed, string.concat(contractKey, ": re-derived address does not match canonical-v1.0.1.json")
        );
    }

    function _manifest() internal view returns (string memory) {
        return vm.readFile(MANIFEST);
    }
}
