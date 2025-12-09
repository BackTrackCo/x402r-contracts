// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IMerchantEscrow {
    function noteDeposit(address user, uint256 amount) external;
    function deposits(address user) external view returns (uint256 principal, uint256 timestamp);
    function release(address user) external;
    function refund(address user) external;
}

