-- x402r: Total Payment Volume by Chain
--
-- Step 1: Discover all operator addresses from known factory contracts (fast, filtered by contract_address)
-- Step 2: Filter payment events to only those operator addresses
--
-- OperatorDeployed topic0: 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
--   topic1 = operator address
-- AuthorizationCreated topic0: 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
-- ChargeExecuted topic0:       0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
-- data layout: amount(uint256) at bytes 1-32

WITH operators AS (
    SELECT 'base' AS chain, bytearray_substring(topic1, 13, 20) AS operator FROM base.logs
    WHERE contract_address = 0x3D0837fF8Ea36F417261577b9BA568400A840260
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'ethereum', bytearray_substring(topic1, 13, 20) FROM ethereum.logs
    WHERE contract_address = 0x1e52a74cE6b69F04a506eF815743E1052A1BD28F
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'polygon', bytearray_substring(topic1, 13, 20) FROM polygon.logs
    WHERE contract_address = 0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'arbitrum', bytearray_substring(topic1, 13, 20) FROM arbitrum.logs
    WHERE contract_address = 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'optimism', bytearray_substring(topic1, 13, 20) FROM optimism.logs
    WHERE contract_address = 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'celo', bytearray_substring(topic1, 13, 20) FROM celo.logs
    WHERE contract_address = 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
    UNION ALL
    SELECT 'avalanche_c', bytearray_substring(topic1, 13, 20) FROM avalanche_c.logs
    WHERE contract_address = 0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6
      AND topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
),

raw_logs AS (
    SELECT 'base' AS chain, topic0, data, contract_address FROM base.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'base')
    UNION ALL
    SELECT 'ethereum', topic0, data, contract_address FROM ethereum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'ethereum')
    UNION ALL
    SELECT 'polygon', topic0, data, contract_address FROM polygon.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'polygon')
    UNION ALL
    SELECT 'arbitrum', topic0, data, contract_address FROM arbitrum.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'arbitrum')
    UNION ALL
    SELECT 'optimism', topic0, data, contract_address FROM optimism.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'optimism')
    UNION ALL
    SELECT 'celo', topic0, data, contract_address FROM celo.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'celo')
    UNION ALL
    SELECT 'avalanche_c', topic0, data, contract_address FROM avalanche_c.logs
    WHERE topic0 IN (0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d,
                     0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00)
      AND contract_address IN (SELECT operator FROM operators WHERE chain = 'avalanche_c')
),

parsed AS (
    SELECT
        chain,
        contract_address AS operator,
        CASE
            WHEN topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d THEN 'authorize'
            ELSE 'charge'
        END AS event_type,
        bytearray_to_uint256(bytearray_substring(data, 1, 32)) AS amount_raw
    FROM raw_logs
)

SELECT
    COALESCE(chain, 'TOTAL') AS chain,
    COUNT(*) FILTER (WHERE event_type = 'authorize') AS auth_count,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'authorize') AS double) / 1e6 AS auth_volume_usdc,
    COUNT(*) FILTER (WHERE event_type = 'charge') AS charge_count,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'charge') AS double) / 1e6 AS charge_volume_usdc,
    COUNT(*) AS total_txns,
    CAST(SUM(amount_raw) AS double) / 1e6 AS gross_volume_usdc
FROM parsed
GROUP BY ROLLUP(chain)
ORDER BY CASE WHEN chain IS NULL THEN 1 ELSE 0 END, gross_volume_usdc DESC
