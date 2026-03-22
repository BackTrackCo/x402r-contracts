-- x402r: Daily Volume Time Series
--
-- AuthorizationCreated + ChargeExecuted grouped by day across all chains.

WITH raw_logs AS (
    SELECT 'base' AS chain, block_time, data FROM base.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'ethereum', block_time, data FROM ethereum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'polygon', block_time, data FROM polygon.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'arbitrum', block_time, data FROM arbitrum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'optimism', block_time, data FROM optimism.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'celo', block_time, data FROM celo.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'avalanche_c', block_time, data FROM avalanche_c.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'linea', block_time, data FROM linea.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
)

SELECT
    chain,
    DATE_TRUNC('day', block_time) AS day,
    COUNT(*) AS txn_count,
    CAST(SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32))) AS double) / 1e6 AS volume_usdc
FROM raw_logs
GROUP BY chain, DATE_TRUNC('day', block_time)
ORDER BY day DESC
