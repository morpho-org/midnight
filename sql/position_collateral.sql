-- Reconstructs position[id][user].collateral[index] from events.
-- Returns one row per (id, user, collateral_index) with the current collateral amount.
-- collateralBitmap is derived: bit i is set iff amount > 0.
-- Platform: Dune Analytics (Trino SQL, native uint256)
--
-- Assumption: midnight.midnight_evt_marketcreated has a column
--   market_collateralparams  of type ARRAY(ROW(token VARBINARY, lltv UINT256, maxlif UINT256, oracle VARBINARY))
-- allowing UNNEST with ORDINALITY to recover collateral_index from token address.

WITH

-- Build a (market_id, token, collateral_index) lookup from MarketCreated.
-- ORDINALITY starts at 1; subtract 1 to match the 0-based Solidity array index.
collateral_index_lookup AS (
    SELECT
        id_,
        cp.token                  AS collateral_token,
        CAST(idx - 1 AS uint256)  AS collateral_index
    FROM midnight.midnight_evt_marketcreated
    CROSS JOIN UNNEST(market_collateralparams) WITH ORDINALITY AS t(cp, idx)
),

-- ── Collateral deltas ─────────────────────────────────────────────────────────
-- SupplyCollateral: +assets
-- WithdrawCollateral: -assets
-- Liquidate: -seizedAssets (for the liquidated collateral only)

collateral_deltas AS (
    SELECT
        s.id_,
        s.onbehalf   AS user,
        cil.collateral_index,
        s.assets     AS add_,
        UINT256 '0'  AS sub_
    FROM midnight.midnight_evt_supplycollateral s
    JOIN collateral_index_lookup cil
        ON cil.id_ = s.id_ AND cil.collateral_token = s.collateral

    UNION ALL

    SELECT
        w.id_,
        w.onbehalf   AS user,
        cil.collateral_index,
        UINT256 '0'  AS add_,
        w.assets     AS sub_
    FROM midnight.midnight_evt_withdrawcollateral w
    JOIN collateral_index_lookup cil
        ON cil.id_ = w.id_ AND cil.collateral_token = w.collateral

    UNION ALL

    SELECT
        l.id_,
        l.borrower   AS user,
        cil.collateral_index,
        UINT256 '0'  AS add_,
        l.seizedassets AS sub_
    FROM midnight.midnight_evt_liquidate l
    JOIN collateral_index_lookup cil
        ON cil.id_ = l.id_ AND cil.collateral_token = l.collateral
),

aggregated AS (
    SELECT
        id_,
        user,
        collateral_index,
        SUM(add_) - SUM(sub_) AS amount
    FROM collateral_deltas
    GROUP BY id_, user, collateral_index
)

SELECT
    id_,
    user,
    collateral_index,
    amount,
    -- collateralBitmap: bit i is set iff amount > 0
    -- Reconstruct as a bitmask: SUM over all indices with set bits
    -- (computed separately per user in the outer query if needed)
    amount > UINT256 '0' AS bit_is_set
FROM aggregated
WHERE amount > UINT256 '0'
