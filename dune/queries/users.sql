-- x402r: Unique Payers and Receivers
--
-- AuthorizationCreated + ChargeExecuted: topic2 = payer, topic3 = receiver

WITH raw_logs AS (
    SELECT 'base' AS chain, topic2, topic3 FROM base.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'ethereum', topic2, topic3 FROM ethereum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'polygon', topic2, topic3 FROM polygon.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'arbitrum', topic2, topic3 FROM arbitrum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'optimism', topic2, topic3 FROM optimism.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'celo', topic2, topic3 FROM celo.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'avalanche_c', topic2, topic3 FROM avalanche_c.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
    UNION ALL
    SELECT 'linea', topic2, topic3 FROM linea.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
)

SELECT
    chain,
    COUNT(DISTINCT topic2) AS unique_payers,
    COUNT(DISTINCT topic3) AS unique_receivers,
    COUNT(*) AS total_payments
FROM raw_logs
GROUP BY chain
ORDER BY total_payments DESC
