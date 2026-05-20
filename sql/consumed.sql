-- Reconstructs consumed[user][group] from events.
-- Both Take and SetConsumed emit the ABSOLUTE current value (not a delta).
-- Returns the last value per (user, group).
-- Platform: Dune Analytics (Trino SQL, native uint256)
--
-- In Take:      consumed[offer.maker][offer.group] = consumed field (newConsumed after increment)
-- In SetConsumed: consumed[onBehalf][group] = amount (monotone set, may skip to max to cancel)

WITH

all_consumed_updates AS (
    -- From Take: the offer's maker consumed amount is updated
    SELECT
        maker                    AS user,
        "group"                  AS "group",
        consumed                 AS amount,
        evt_block_number,
        evt_index
    FROM midnight.midnight_evt_take

    UNION ALL

    -- From SetConsumed: explicit set (e.g. to cancel all offers in a group)
    SELECT
        onbehalf                 AS user,
        "group"                  AS "group",
        amount                   AS amount,
        evt_block_number,
        evt_index
    FROM midnight.midnight_evt_setconsumed
)

SELECT user, "group", amount
FROM (
    SELECT
        user,
        "group",
        amount,
        ROW_NUMBER() OVER (
            PARTITION BY user, "group"
            ORDER BY evt_block_number DESC, evt_index DESC
        ) AS rn
    FROM all_consumed_updates
)
WHERE rn = 1
