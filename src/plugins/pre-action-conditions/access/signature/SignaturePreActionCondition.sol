// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {IPreActionCondition} from "../../IPreActionCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../../../../operator/payment/PaymentOperator.sol";

/**
 * @title SignaturePreActionCondition
 * @notice Condition that checks for a valid EIP-712 signature approval.
 *         Decouples authorization (signing) from execution (tx submission).
 * @dev The SIGNER signs an EIP-712 typed Approval off-chain. Anyone can submit
 *      the signature via submitApproval() to store the approval on-chain.
 *      check() then reads stored approvals — it's pure view, never reverts.
 *
 *      Uses Solady's SignatureCheckerLib which supports both EOA (ecrecover)
 *      and EIP-1271 contract signers (smart wallets, multi-arbiter aggregators).
 *
 *      REPLAY PROTECTION: Each approval includes a per-paymentInfoHash nonce that
 *      auto-increments on each submitApproval(). This prevents stale signatures
 *      from being replayed to overwrite newer approvals with older values.
 */
contract SignaturePreActionCondition is IPreActionCondition, EIP712 {
    /// @notice The authorized signer (EOA or EIP-1271 contract)
    address public immutable SIGNER;

    struct StoredApproval {
        uint256 amount;
        uint48 expiry;
    }

    /// @notice Stored approvals keyed by paymentInfoHash
    mapping(bytes32 paymentInfoHash => StoredApproval) public approvals;

    /// @notice Per-paymentInfoHash nonce for replay protection
    /// @dev Increments on each submitApproval(). Signer must include current nonce in signature.
    mapping(bytes32 paymentInfoHash => uint256) public approvalNonces;

    bytes32 public constant APPROVAL_TYPEHASH =
        keccak256("Approval(bytes32 paymentInfoHash,uint256 amount,uint48 expiry,uint256 nonce)");

    event ApprovalSubmitted(bytes32 indexed paymentInfoHash, uint256 amount, uint48 expiry, uint256 nonce);

    error InvalidSignature();
    error InvalidNonce();
    error ZeroSigner();

    constructor(address _signer) {
        if (_signer == address(0)) revert ZeroSigner();
        SIGNER = _signer;
    }

    /// @dev Solady EIP712 requires these overrides for domain separator
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "SignaturePreActionCondition";
        version = "1";
    }

    /// @notice Submit an off-chain approval signature to store the approval on-chain
    /// @param paymentInfoHash The hash of the PaymentInfo struct
    /// @param amount Maximum approved refund amount (check passes for <= this)
    /// @param expiry Unix timestamp deadline (0 = no expiry)
    /// @param nonce Must match current approvalNonces[paymentInfoHash] (prevents replay)
    /// @param signature The EIP-712 signature from SIGNER
    function submitApproval(
        bytes32 paymentInfoHash,
        uint256 amount,
        uint48 expiry,
        uint256 nonce,
        bytes calldata signature
    ) external {
        // ============ CHECKS ============
        uint256 currentNonce = approvalNonces[paymentInfoHash];
        if (nonce != currentNonce) revert InvalidNonce();

        bytes32 digest =
            _hashTypedData(keccak256(abi.encode(APPROVAL_TYPEHASH, paymentInfoHash, amount, expiry, nonce)));
        // SignatureCheckerLib: ecrecover for EOAs, EIP-1271 fallback for contracts
        if (!SignatureCheckerLib.isValidSignatureNow(SIGNER, digest, signature)) {
            revert InvalidSignature();
        }

        // ============ EFFECTS ============
        approvals[paymentInfoHash] = StoredApproval({amount: amount, expiry: expiry});
        approvalNonces[paymentInfoHash] = currentNonce + 1;
        emit ApprovalSubmitted(paymentInfoHash, amount, expiry, nonce);
    }

    /// @notice Check if an approved refund exists for the given payment
    /// @param paymentInfo The payment information
    /// @param amount The refund amount being requested
    /// @return True if a valid approval exists for this amount
    function check(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address, /* caller */
        bytes calldata /* data */
    )
        external
        view
        override
        returns (bool)
    {
        bytes32 key = PaymentOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo);
        StoredApproval storage approval = approvals[key];
        if (approval.amount == 0) return false;
        if (amount > approval.amount) return false;
        if (approval.expiry != 0 && block.timestamp > approval.expiry) return false;
        return true;
    }
}
