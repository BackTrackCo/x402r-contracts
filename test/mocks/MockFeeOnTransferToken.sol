// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockFeeOnTransferToken
 * @notice Mock ERC20 token that takes a fee on every transfer
 * @dev Used for testing fee-on-transfer token rejection
 *      Examples: STA (Statera), PAXG (Paxos Gold), cUSDCv3
 */
contract MockFeeOnTransferToken is ERC20 {
    uint256 public constant TRANSFER_FEE_BPS = 100; // 1% fee

    constructor() ERC20("Mock Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Override transfer to take fee
     * @dev Fee is burned (could also be sent to fee collector)
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * TRANSFER_FEE_BPS) / 10000;
        uint256 amountAfterFee = amount - fee;

        // Burn the fee
        _burn(msg.sender, fee);

        // Transfer the rest
        return super.transfer(to, amountAfterFee);
    }

    /**
     * @notice Override transferFrom to take fee
     * @dev Fee is burned (could also be sent to fee collector)
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * TRANSFER_FEE_BPS) / 10000;
        uint256 amountAfterFee = amount - fee;

        // Burn the fee
        _burn(from, fee);

        // Transfer the rest (this will also handle approval)
        _transfer(from, to, amountAfterFee);

        // Update allowance
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance != type(uint256).max) {
            _approve(from, msg.sender, currentAllowance - amount);
        }

        return true;
    }
}
