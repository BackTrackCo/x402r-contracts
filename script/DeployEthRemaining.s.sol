// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";
import {
    StaticAddressConditionFactory
} from "../src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {RecorderCombinatorFactory} from "../src/plugins/recorders/combinators/RecorderCombinatorFactory.sol";

/**
 * @title DeployEthRemaining
 * @notice Deploy remaining contracts on Ethereum mainnet (ran out of gas on first deploy)
 */
contract DeployEthRemaining is Script {
    function run() external {
        // Escrow already deployed at this address on Ethereum mainnet
        address escrow = 0xc1256Bb30bd0cdDa07D8C8Cf67a59105f2EA1b98;

        vm.startBroadcast();

        ReceiverCondition receiverCondition = new ReceiverCondition();
        console.log("receiverCondition:", address(receiverCondition));

        AlwaysTrueCondition alwaysTrueCondition = new AlwaysTrueCondition();
        console.log("alwaysTrueCondition:", address(alwaysTrueCondition));

        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(escrow);
        console.log("escrowPeriodFactory:", address(escrowPeriodFactory));

        FreezeFactory freezeFactory = new FreezeFactory(escrow);
        console.log("freezeFactory:", address(freezeFactory));

        StaticFeeCalculatorFactory staticFeeCalcFactory = new StaticFeeCalculatorFactory();
        console.log("staticFeeCalculatorFactory:", address(staticFeeCalcFactory));

        StaticAddressConditionFactory staticAddrCondFactory = new StaticAddressConditionFactory();
        console.log("staticAddressConditionFactory:", address(staticAddrCondFactory));

        AndConditionFactory andFactory = new AndConditionFactory();
        console.log("andConditionFactory:", address(andFactory));

        OrConditionFactory orFactory = new OrConditionFactory();
        console.log("orConditionFactory:", address(orFactory));

        NotConditionFactory notFactory = new NotConditionFactory();
        console.log("notConditionFactory:", address(notFactory));

        RecorderCombinatorFactory recorderCombFactory = new RecorderCombinatorFactory();
        console.log("recorderCombinatorFactory:", address(recorderCombFactory));

        vm.stopBroadcast();
    }
}
