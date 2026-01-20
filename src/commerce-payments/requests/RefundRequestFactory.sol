// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RefundRequest} from "./refund/RefundRequest.sol";
import {ZeroOperator} from "./types/Errors.sol";
import {RefundRequestDeployed} from "./types/Events.sol";
import {ArbitrationOperatorFactory} from "../operator/ArbitrationOperatorFactory.sol";

/**
 * @title RefundRequestFactory
 * @notice Factory contract that deploys RefundRequest instances for ArbitrationOperator contracts.
 *
 * @dev Design rationale:
 *      - Each operator gets one RefundRequest contract (1:1 mapping)
 *      - Idempotent deployment - returns existing if already deployed
 *      - Anyone can deploy a RefundRequest for an operator
 *      - Convenience method to deploy both operator and refund request together
 */
contract RefundRequestFactory {
    ArbitrationOperatorFactory public immutable OPERATOR_FACTORY;

    // operator => refundRequest address
    mapping(address => address) public refundRequests;

    constructor(address _operatorFactory) {
        if (_operatorFactory == address(0)) revert ZeroOperator();
        OPERATOR_FACTORY = ArbitrationOperatorFactory(_operatorFactory);
    }

    /**
     * @notice Get the refund request address for a given operator
     * @param operator The operator address
     * @return refundRequest The refund request address (address(0) if not deployed)
     */
    function getRefundRequest(address operator) external view returns (address) {
        return refundRequests[operator];
    }

    /**
     * @notice Deploy a refund request contract for an existing operator
     * @dev Idempotent - returns existing refund request if already deployed.
     * @param operator The operator address to create a refund request for
     * @return refundRequest The refund request address
     */
    function deployRefundRequest(address operator) public returns (address refundRequest) {
        if (operator == address(0)) revert ZeroOperator();

        // Return existing if already deployed (idempotent)
        if (refundRequests[operator] != address(0)) {
            return refundRequests[operator];
        }

        // Deploy new refund request tied to this operator
        refundRequest = address(new RefundRequest(operator));

        refundRequests[operator] = refundRequest;

        emit RefundRequestDeployed(refundRequest, operator);

        return refundRequest;
    }

    /**
     * @notice Deploy both an operator and its refund request contract
     * @dev Convenience method that calls ArbitrationOperatorFactory.deployOperator()
     *      and then deploys a RefundRequest for the resulting operator.
     *      Both deployments are idempotent.
     * @param arbiter The arbiter address
     * @param escrowPeriod The escrow period in seconds
     * @return operator The operator address
     * @return refundRequest The refund request address
     */
    function deployOperatorAndRefundRequest(
        address arbiter,
        uint48 escrowPeriod
    ) external returns (address operator, address refundRequest) {
        // Deploy operator (idempotent - returns existing if already deployed)
        operator = OPERATOR_FACTORY.deployOperator(arbiter, escrowPeriod);

        // Deploy refund request for the operator (idempotent)
        refundRequest = deployRefundRequest(operator);

        return (operator, refundRequest);
    }
}
