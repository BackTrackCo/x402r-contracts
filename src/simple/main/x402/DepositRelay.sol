// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC3009} from "../../interfaces/IERC3009.sol";
import {Escrow} from "../escrow/Escrow.sol";

contract DepositRelay {
    address public immutable TOKEN;

    constructor(address _token) {
        TOKEN = _token;
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
        IERC3009(TOKEN).transferWithAuthorization(
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

