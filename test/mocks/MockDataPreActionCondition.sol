// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPreActionCondition} from "../../src/plugins/pre-action-conditions/IPreActionCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockDataPreActionCondition
 * @notice Mock condition that requires non-empty data and decodes a magic value from it.
 *         Used to verify that the `data` parameter is correctly forwarded end-to-end
 *         through PaymentOperator to conditions.
 */
contract MockDataPreActionCondition is IPreActionCondition {
    /// @notice The magic value that must be encoded in `data` for the check to pass
    bytes32 public immutable EXPECTED_MAGIC;

    /// @notice Tracks the last data received for test assertions
    bytes public lastReceivedData;

    constructor(bytes32 expectedMagic) {
        EXPECTED_MAGIC = expectedMagic;
    }

    /**
     * @notice Check that data is non-empty and contains the expected magic value
     * @param data Must be abi.encode(bytes32) matching EXPECTED_MAGIC
     * @return allowed True if data decodes to the expected magic value
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata, uint256, address, bytes calldata data)
        external
        view
        override
        returns (bool allowed)
    {
        if (data.length == 0) return false;
        if (data.length < 32) return false;
        bytes32 magic = abi.decode(data, (bytes32));
        return magic == EXPECTED_MAGIC;
    }
}
