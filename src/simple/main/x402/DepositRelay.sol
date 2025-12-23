// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3009} from "../../interfaces/IERC3009.sol";
import {Escrow} from "../escrow/Escrow.sol";

/**
 * @title DepositRelay
 * @notice Deposit relay implementation for refund extension
 * @dev Reads data directly from proxy storage (no factory queries needed).
 *      This implementation is specific to the refund use case.
 *      The proxy delegates all calls here, and this contract handles the refund logic.
 *      
 *      Since this runs via delegatecall, address(this) refers to the proxy.
 *      We can directly read from the proxy's immutable storage.
 */
contract DepositRelay {
    using SafeERC20 for IERC20;
    /**
     * @notice Execute deposit by reading from proxy storage and processing payment
     * @dev Called via delegatecall from RelayProxy.
     *      Reads merchantPayout, token, and escrow directly from proxy storage.
     */
    function executeDeposit(
        address fromUser,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Read directly from proxy storage (via delegatecall, address(this) is the proxy)
        // Since immutables are stored in bytecode, we read them via staticcall
        address merchantPayout = _readImmutable("MERCHANT_PAYOUT()");
        address token = _readImmutable("TOKEN()");
        address escrow = _readImmutable("ESCROW()");
        
        require(merchantPayout != address(0), "DepositRelay: Zero merchant payout");
        require(token != address(0), "DepositRelay: Zero token");
        require(escrow != address(0), "DepositRelay: Zero escrow");
        require(fromUser != address(0), "DepositRelay: Zero fromUser");
        require(amount > 0, "DepositRelay: Zero amount");
        
        // Check if merchant is registered
        bool isRegistered;
        try Escrow(escrow).registeredMerchants(merchantPayout) returns (bool registered) {
            isRegistered = registered;
        } catch {
            revert("DepositRelay: Failed to check merchant registration");
        }
        require(isRegistered, "DepositRelay: Merchant not registered");
        
        // In delegatecall context, address(this) refers to the RelayProxy contract address
        // This is the address that X402 payment payload signs the ERC3009 transfer for
        address relayProxyAddress = address(this);
        
        // Pull token via ERC3009 - use relayProxyAddress as recipient
        // X402 payment payload signs: transferWithAuthorization(from, to=relayProxyAddress, amount, ...)
        // Note: Even though msg.sender is the proxy when called via delegatecall, the signature
        // validation should still work because it only checks the signed parameters, not msg.sender
        try IERC3009(token).transferWithAuthorization(
            fromUser,
            relayProxyAddress, // Must match the 'to' address in the X402 signature (RelayProxy address)
            amount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        ) {
            // Success - continue
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("DepositRelay: transferWithAuthorization failed - ", reason)));
        } catch {
            revert("DepositRelay: transferWithAuthorization failed with low-level revert");
        }

        // Verify tokens were received by relay proxy
        uint256 balanceAfterTransfer = IERC20(token).balanceOf(relayProxyAddress);
        require(balanceAfterTransfer >= amount, "DepositRelay: Insufficient balance after transferWithAuthorization");

        // Transfer tokens from relay proxy to escrow using SafeERC20
        // This handles tokens that don't return booleans (like USDC) and provides better error handling
        IERC20(token).safeTransfer(escrow, amount);
        
        // Verify escrow received the tokens
        uint256 escrowBalance = IERC20(token).balanceOf(escrow);
        require(escrowBalance >= amount, "DepositRelay: Escrow did not receive tokens");

        // Notify escrow with merchantPayout
        try Escrow(escrow).noteDeposit(fromUser, merchantPayout, amount) returns (uint256 /* depositNonce */) {
            // Success - deposit noted
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("DepositRelay: noteDeposit failed - ", reason)));
        } catch {
            revert("DepositRelay: noteDeposit failed with low-level revert");
        }
    }
    
    /**
     * @notice Helper to read immutable values from proxy storage
     * @param signature Function signature to call (e.g., "MERCHANT_PAYOUT()")
     * @return The address value stored in the immutable
     */
    function _readImmutable(string memory signature) internal view returns (address) {
        (bool success, bytes memory data) = address(this).staticcall(
            abi.encodeWithSignature(signature)
        );
        require(success && data.length >= 32, "Immutable read failed");
        return abi.decode(data, (address));
    }
}

