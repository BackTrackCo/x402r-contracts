// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../interfaces/IERC3009.sol";
import "../escrow/Escrow.sol";

contract DepositRelay {
    address public immutable token;

    constructor(address _token) {
        token = _token;
    }

    function executeDeposit(
        address merchantEscrow,
        address fromUser,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Pull USDC via ERC3009
        IERC3009(token).transferWithAuthorization(
            fromUser,
            merchantEscrow,
            amount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        // Notify escrow
        Escrow(merchantEscrow).noteDeposit(fromUser, amount);
    }
}

