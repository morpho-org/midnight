-- Reconstructs isAuthorized[authorizer][authorized] from events.
-- Returns the last newIsAuthorized value per (authorizer, authorized) pair.
-- Platform: Dune Analytics (Trino SQL)

SELECT authorizer, authorized, is_authorized
FROM (
    SELECT
        onbehalf            AS authorizer,
        authorized          AS authorized,
        newisauthorized     AS is_authorized,
        ROW_NUMBER() OVER (
            PARTITION BY onbehalf, authorized
            ORDER BY evt_block_number DESC, evt_index DESC
        ) AS rn
    FROM midnight.midnight_evt_setisauthorized
)
WHERE rn = 1
