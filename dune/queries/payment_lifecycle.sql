-- x402r: Payment Lifecycle — Auth → Release → Refund
--
-- Full payment flow across all chains from PaymentOperator events.
--
-- Event data layouts:
--   AuthorizationCreated:      data = amount(32) | timestamp(32)
--   ChargeExecuted:            data = amount(32) | timestamp(32)
--   ReleaseExecuted:           data = paymentInfo(384) | amount(32) | timestamp(32)
--   RefundInEscrowExecuted:    data = paymentInfo(384) | amount(32)
--   RefundPostEscrowExecuted:  data = paymentInfo(384) | amount(32)

WITH events AS (
    -- AuthorizationCreated
    SELECT 'base' AS chain, 'authorized' AS event_type,
           bytearray_to_uint256(bytearray_substring(data, 1, 32)) AS amount_raw
    FROM base.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'ethereum', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM ethereum.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'polygon', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM polygon.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'arbitrum', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM arbitrum.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'optimism', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM optimism.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'celo', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM celo.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d
    UNION ALL
    SELECT 'avalanche_c', 'authorized',
           bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM avalanche_c.logs WHERE topic0 = 0x25a881a7e96f8ce977da598bc17f91f1235aa59b7a2abad5f454f317c7ff2c9d

    UNION ALL

    -- ChargeExecuted
    SELECT 'base', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM base.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'ethereum', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM ethereum.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'polygon', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM polygon.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'arbitrum', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM arbitrum.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'optimism', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM optimism.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'celo', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM celo.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00
    UNION ALL
    SELECT 'avalanche_c', 'charged', bytearray_to_uint256(bytearray_substring(data, 1, 32))
    FROM avalanche_c.logs WHERE topic0 = 0xdb91bd6597cd642062d7480a3e7a9510af3cac44b224cf7ae9357a8e18af0d00

    UNION ALL

    -- ReleaseExecuted: amount at data offset 385 (after 384-byte paymentInfo tuple)
    SELECT 'base', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM base.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'ethereum', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM ethereum.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'polygon', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM polygon.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'arbitrum', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM arbitrum.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'optimism', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM optimism.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'celo', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM celo.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57
    UNION ALL
    SELECT 'avalanche_c', 'released', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM avalanche_c.logs WHERE topic0 = 0xef37646753b7da2c4dc22b8f3e7ea02b5db09ea73db9f331c2dc86a796e36a57

    UNION ALL

    -- RefundInEscrowExecuted: amount at data offset 385
    SELECT 'base', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM base.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'ethereum', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM ethereum.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'polygon', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM polygon.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'arbitrum', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM arbitrum.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'optimism', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM optimism.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'celo', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM celo.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd
    UNION ALL
    SELECT 'avalanche_c', 'refund_escrow', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM avalanche_c.logs WHERE topic0 = 0x4636fb10066996aa522c42989c534e9c535fb8573b5ad9b84fc5d17512a825bd

    UNION ALL

    -- RefundPostEscrowExecuted: amount at data offset 385
    SELECT 'base', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM base.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'ethereum', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM ethereum.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'polygon', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM polygon.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'arbitrum', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM arbitrum.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'optimism', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM optimism.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'celo', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM celo.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
    UNION ALL
    SELECT 'avalanche_c', 'refund_post', bytearray_to_uint256(bytearray_substring(data, 385, 32))
    FROM avalanche_c.logs WHERE topic0 = 0x1459169da64152ba94c628f131a9dec359224a3d1aab588ffb69a49ddf3faeae
)

SELECT
    chain,
    COUNT(*) FILTER (WHERE event_type = 'authorized') AS authorizations,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'authorized') AS double) / 1e6 AS auth_volume_usdc,
    COUNT(*) FILTER (WHERE event_type = 'charged') AS charges,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'charged') AS double) / 1e6 AS charge_volume_usdc,
    COUNT(*) FILTER (WHERE event_type = 'released') AS releases,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'released') AS double) / 1e6 AS release_volume_usdc,
    COUNT(*) FILTER (WHERE event_type = 'refund_escrow') AS refunds_in_escrow,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'refund_escrow') AS double) / 1e6 AS refund_escrow_usdc,
    COUNT(*) FILTER (WHERE event_type = 'refund_post') AS refunds_post_escrow,
    CAST(SUM(amount_raw) FILTER (WHERE event_type = 'refund_post') AS double) / 1e6 AS refund_post_usdc,
    (CAST(COALESCE(SUM(amount_raw) FILTER (WHERE event_type = 'released'), 0) AS double)
     + CAST(COALESCE(SUM(amount_raw) FILTER (WHERE event_type = 'charged'), 0) AS double)
     - CAST(COALESCE(SUM(amount_raw) FILTER (WHERE event_type = 'refund_post'), 0) AS double)
    ) / 1e6 AS net_captured_usdc
FROM events
GROUP BY chain
ORDER BY auth_volume_usdc DESC
