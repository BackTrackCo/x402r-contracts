-- x402r: Deployed Operators
--
-- OperatorDeployed(address indexed operator, address indexed feeRecipient, address releaseCondition)
--   topic0: 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
--   topic1: operator address (indexed)
--   topic2: feeRecipient address (indexed)
--   data: releaseCondition (address, padded to 32 bytes)
--
-- Tracks both legacy per-chain factories and unified CREATE3 factory (0xdc41F932...)

WITH raw_logs AS (
    SELECT 'base' AS chain, block_time, tx_hash, contract_address, topic1, topic2, data FROM base.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x3D0837fF8Ea36F417261577b9BA568400A840260, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'ethereum', block_time, tx_hash, contract_address, topic1, topic2, data FROM ethereum.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x1e52a74cE6b69F04a506eF815743E1052A1BD28F, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'polygon', block_time, tx_hash, contract_address, topic1, topic2, data FROM polygon.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0xb33D6502EdBbC47201cd1E53C49d703EC0a660b8, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'arbitrum', block_time, tx_hash, contract_address, topic1, topic2, data FROM arbitrum.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'optimism', block_time, tx_hash, contract_address, topic1, topic2, data FROM optimism.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'celo', block_time, tx_hash, contract_address, topic1, topic2, data FROM celo.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'avalanche_c', block_time, tx_hash, contract_address, topic1, topic2, data FROM avalanche_c.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address IN (0x32d6AC59BCe8DFB3026F10BcaDB8D00AB218f5b6, 0xdc41F932dF2d22346F218E4f5650694c650ab863)
    UNION ALL
    SELECT 'linea', block_time, tx_hash, contract_address, topic1, topic2, data FROM linea.logs
    WHERE topic0 = 0xecf5e5f1fec1eb36d3fb535d9f789157daaaef2d1dce54e4c09b5631ae9efa10
      AND contract_address = 0xdc41F932dF2d22346F218E4f5650694c650ab863
)

SELECT
    chain,
    block_time AS deployed_at,
    tx_hash,
    contract_address AS factory,
    topic1 AS operator,
    topic2 AS fee_recipient
FROM raw_logs
ORDER BY block_time DESC
