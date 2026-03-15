-- x402r: Payment Volume by Operator
--
-- Breaks down volume per PaymentOperator contract address per chain.
-- AuthorizationCreated: topic2 = payer, topic3 = receiver, data[1:32] = amount
-- ChargeExecuted:       topic2 = payer, topic3 = receiver, data[1:32] = amount

WITH raw_logs AS (
    SELECT 'base' AS chain, topic0, topic2, topic3, data, contract_address FROM base.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'ethereum', topic0, topic2, topic3, data, contract_address FROM ethereum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'polygon', topic0, topic2, topic3, data, contract_address FROM polygon.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'arbitrum', topic0, topic2, topic3, data, contract_address FROM arbitrum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'optimism', topic0, topic2, topic3, data, contract_address FROM optimism.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'celo', topic0, topic2, topic3, data, contract_address FROM celo.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'avalanche_c', topic0, topic2, topic3, data, contract_address FROM avalanche_c.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
)

SELECT
    chain,
    contract_address AS operator,
    COUNT(*) AS total_txns,
    CAST(SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32))) AS double) / 1e6 AS gross_volume_usdc,
    COUNT(*) FILTER (WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d) AS auth_count,
    COUNT(*) FILTER (WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00) AS charge_count,
    COUNT(DISTINCT topic2) AS unique_payers,
    COUNT(DISTINCT topic3) AS unique_receivers
FROM raw_logs
GROUP BY chain, contract_address
ORDER BY gross_volume_usdc DESC
