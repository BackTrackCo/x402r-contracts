// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";

/**
 * @title MockRebasingToken
 * @notice Mock ERC20 token that rebases balances
 * @dev Used for testing rebasing token behavior
 *      Examples: AMPL (Ampleforth), stETH (approximation), RAI
 */
contract MockRebasingToken is ERC20 {
    uint256 private _totalShares;
    mapping(address => uint256) private _shares;
    uint256 public rebaseMultiplier = 1e18; // 1.0 multiplier initially

    function name() public pure override returns (string memory) {
        return "Mock Rebase Token";
    }

    function symbol() public pure override returns (string memory) {
        return "REBASE";
    }

    /**
     * @notice Simulate a rebase event
     * @param newMultiplier New multiplier (1e18 = 1.0, 1.1e18 = 1.1, etc.)
     * @dev Positive rebase increases all balances, negative decreases
     */
    function rebase(uint256 newMultiplier) external {
        rebaseMultiplier = newMultiplier;
    }

    /**
     * @notice Mint shares to an address
     * @param to Recipient address
     * @param amount Amount of tokens to mint (in token units, not shares)
     */
    function mint(address to, uint256 amount) external {
        uint256 shares = (amount * 1e18) / rebaseMultiplier;
        _shares[to] += shares;
        _totalShares += shares;
    }

    /**
     * @notice Get balance of an address (rebased)
     * @param account Address to query
     * @return Balance in token units (affected by rebase)
     */
    function balanceOf(address account) public view override returns (uint256) {
        return (_shares[account] * rebaseMultiplier) / 1e18;
    }

    /**
     * @notice Get total supply (rebased)
     * @return Total supply in token units (affected by rebase)
     */
    function totalSupply() public view override returns (uint256) {
        return (_totalShares * rebaseMultiplier) / 1e18;
    }

    /**
     * @notice Transfer tokens (transfers shares, so balance changes with rebase)
     * @param to Recipient
     * @param amount Amount in token units
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 shares = (amount * 1e18) / rebaseMultiplier;
        require(_shares[msg.sender] >= shares, "Insufficient balance");

        _shares[msg.sender] -= shares;
        _shares[to] += shares;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice TransferFrom tokens
     * @param from Sender
     * @param to Recipient
     * @param amount Amount in token units
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 shares = (amount * 1e18) / rebaseMultiplier;
        require(_shares[from] >= shares, "Insufficient balance");

        // Check allowance
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "Insufficient allowance");

        _shares[from] -= shares;
        _shares[to] += shares;

        // Update allowance
        if (currentAllowance != type(uint256).max) {
            _approve(from, msg.sender, currentAllowance - amount);
        }

        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Get shares for an address (internal accounting)
     * @param account Address to query
     * @return Number of shares (not affected by rebase)
     */
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }
}
