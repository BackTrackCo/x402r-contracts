// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

/**
 * @title RelayProxy
 * @notice Simple proxy that delegates all calls to an implementation
 * @dev Extends OpenZeppelin's Proxy contract for battle-tested delegatecall logic.
 *      Stores all needed data directly (no factory queries needed).
 *      With CREATE3, bytecode size doesn't affect address computation,
 *      so we can use standard, well-audited proxy patterns.
 */
contract RelayProxy is Proxy {
    address public immutable MERCHANT_PAYOUT;
    address public immutable TOKEN;
    address public immutable ESCROW;
    address public immutable IMPLEMENTATION;

    constructor(
        address _merchantPayout,
        address _token,
        address _escrow,
        address implementation_
    ) {
        require(_merchantPayout != address(0), "Zero merchant payout");
        require(_token != address(0), "Zero token");
        require(_escrow != address(0), "Zero escrow");
        require(implementation_ != address(0), "Zero implementation");
        
        MERCHANT_PAYOUT = _merchantPayout;
        TOKEN = _token;
        ESCROW = _escrow;
        IMPLEMENTATION = implementation_;
    }

    /**
     * @notice Returns the implementation address for the proxy
     * @dev Required by OpenZeppelin's Proxy contract
     * @return The implementation contract address
     */
    function _implementation() internal view override returns (address) {
        return IMPLEMENTATION;
    }

    /**
     * @notice Receive function to handle plain Ether transfers
     * @dev This contract should not receive Ether, but we include this for completeness
     */
    receive() external payable {
        revert("RelayProxy: Cannot receive Ether");
    }
}

