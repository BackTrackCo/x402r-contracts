-- x402r: Protocol and Arbiter Fee Collection
--
-- FeesDistributed(address indexed token, uint256 protocolAmount, uint256 arbiterAmount)
--   topic0: 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
--   topic1: token address
--   data: protocolAmount(32) | arbiterAmount(32)

WITH raw_logs AS (
    SELECT 'base' AS chain, contract_address, topic1, data FROM base.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'ethereum', contract_address, topic1, data FROM ethereum.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'polygon', contract_address, topic1, data FROM polygon.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'arbitrum', contract_address, topic1, data FROM arbitrum.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'optimism', contract_address, topic1, data FROM optimism.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'celo', contract_address, topic1, data FROM celo.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'avalanche_c', contract_address, topic1, data FROM avalanche_c.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
    UNION ALL
    SELECT 'linea', contract_address, topic1, data FROM linea.logs
    WHERE topic0 = 0x85da6ab72d2b48932522aea80adb8ca4fab6cdeb87bc2e7f6c03fd78d3b2100e
)

SELECT
    chain,
    contract_address AS operator,
    topic1 AS token,
    COUNT(*) AS fee_events,
    CAST(SUM(bytearray_to_uint256(bytearray_substring(data, 1, 32))) AS double) / 1e6 AS protocol_fees_usdc,
    CAST(SUM(bytearray_to_uint256(bytearray_substring(data, 33, 32))) AS double) / 1e6 AS arbiter_fees_usdc,
    CAST(SUM(
        bytearray_to_uint256(bytearray_substring(data, 1, 32))
        + bytearray_to_uint256(bytearray_substring(data, 33, 32))
    ) AS double) / 1e6 AS total_fees_usdc
FROM raw_logs
GROUP BY chain, contract_address, topic1
ORDER BY total_fees_usdc DESC
