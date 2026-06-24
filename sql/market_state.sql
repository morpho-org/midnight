-- Reconstructs marketState[id] from events.
-- Fields: total_units, loss_factor, withdrawable, continuous_fee_credit,
--         settlement_fee_cbp_0..6, continuous_fee, tick_spacing
-- Platform: Dune Analytics (Trino SQL, native uint256)

WITH

-- ── totalUnits ────────────────────────────────────────────────────────────────
-- Take:             +(buyerCreditIncrease - sellerCreditDecrease)
-- Withdraw:         -units
-- Liquidate:        -badDebt
-- ClaimContinuousFee: -amount

total_units_deltas AS (
    SELECT id_, buyercreditincrease AS add_, sellercreditdecrease AS sub_
    FROM midnight.midnight_evt_take
    UNION ALL
    SELECT id_, UINT256 '0', units          FROM midnight.midnight_evt_withdraw
    UNION ALL
    SELECT id_, UINT256 '0', baddebt        FROM midnight.midnight_evt_liquidate
    UNION ALL
    SELECT id_, UINT256 '0', amount         FROM midnight.midnight_evt_claimcontinuousfee
),

total_units AS (
    SELECT id_, SUM(add_) - SUM(sub_) AS total_units
    FROM total_units_deltas GROUP BY id_
),

-- ── lossFactor: last latestLossFactor per market ──────────────────────────────
-- Initial = 0 (before any liquidation)

loss_factor AS (
    SELECT id_,
           COALESCE(MAX_BY(latestlossfactor, ROW(evt_block_number, evt_index)), UINT256 '0') AS loss_factor
    FROM midnight.midnight_evt_liquidate
    GROUP BY id_
),

-- ── withdrawable ─────────────────────────────────────────────────────────────
-- Repay:              +units
-- Liquidate:          +repaidUnits
-- Withdraw:           -units
-- ClaimContinuousFee: -amount

withdrawable_deltas AS (
    SELECT id_, units   AS add_, UINT256 '0' AS sub_ FROM midnight.midnight_evt_repay
    UNION ALL
    SELECT id_, repaidunits, UINT256 '0'             FROM midnight.midnight_evt_liquidate
    UNION ALL
    SELECT id_, UINT256 '0', units                   FROM midnight.midnight_evt_withdraw
    UNION ALL
    SELECT id_, UINT256 '0', amount                  FROM midnight.midnight_evt_claimcontinuousfee
),

withdrawable AS (
    SELECT id_, SUM(add_) - SUM(sub_) AS withdrawable
    FROM withdrawable_deltas GROUP BY id_
),

-- ── continuousFeeCredit ───────────────────────────────────────────────────────
-- Liquidate emits latestContinuousFeeCredit = the CFC value immediately after
-- the liquidation. Start from the last liquidation's emitted CFC, then add
-- UpdatePosition accruedFee and subtract ClaimContinuousFee amounts that
-- follow it (or process all events if no liquidation has occurred yet).

last_liq AS (
    SELECT id_,
           MAX_BY(latestcontinuousfeecredit, ROW(evt_block_number, evt_index)) AS cfc_after_last_liq,
           MAX_BY(evt_block_number,          ROW(evt_block_number, evt_index)) AS last_liq_block,
           MAX_BY(evt_index,                 ROW(evt_block_number, evt_index)) AS last_liq_index
    FROM midnight.midnight_evt_liquidate
    GROUP BY id_
),

up_after_liq AS (
    SELECT u.id_, SUM(u.accruedfee) AS total_up
    FROM midnight.midnight_evt_updateposition u
    LEFT JOIN last_liq ll ON ll.id_ = u.id_
    WHERE ll.id_ IS NULL
       OR u.evt_block_number > ll.last_liq_block
       OR (u.evt_block_number = ll.last_liq_block AND u.evt_index > ll.last_liq_index)
    GROUP BY u.id_
),

claim_after_liq AS (
    SELECT c.id_, SUM(c.amount) AS total_claim
    FROM midnight.midnight_evt_claimcontinuousfee c
    LEFT JOIN last_liq ll ON ll.id_ = c.id_
    WHERE ll.id_ IS NULL
       OR c.evt_block_number > ll.last_liq_block
       OR (c.evt_block_number = ll.last_liq_block AND c.evt_index > ll.last_liq_index)
    GROUP BY c.id_
),

continuous_fee_credit AS (
    SELECT
        ids.id_,
        COALESCE(ll.cfc_after_last_liq, UINT256 '0')
            + COALESCE(up.total_up,     UINT256 '0')
            - COALESCE(tc.total_claim,  UINT256 '0') AS continuous_fee_credit
    FROM (
             SELECT id_ FROM last_liq
        UNION SELECT id_ FROM up_after_liq
        UNION SELECT id_ FROM claim_after_liq
    ) ids
    LEFT JOIN last_liq        ll ON ll.id_ = ids.id_
    LEFT JOIN up_after_liq    up ON up.id_ = ids.id_
    LEFT JOIN claim_after_liq tc ON tc.id_ = ids.id_
),

-- ── settlementFeeCbp[0..6] and continuousFee ─────────────────────────────────────
-- Initial values come from MarketCreated (= defaults at creation time).
-- Override: SetMarketSettlementFee / SetMarketContinuousFee.

-- Build a combined stream of (id, index, value) for settlement fee per breakpoint.
settlement_fee_stream AS (
    -- MarketCreated seeds all 7 breakpoints (indices 0-6)
    SELECT id_, UINT256 '0' AS index, market_settlementfeecbp0 AS fee, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '1', market_settlementfeecbp1, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '2', market_settlementfeecbp2, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '3', market_settlementfeecbp3, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '4', market_settlementfeecbp4, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '5', market_settlementfeecbp5, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '6', market_settlementfeecbp6, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    -- Overrides (newsettlementfee is raw; divide by CBP to get stored uint16 value)
    UNION ALL
    SELECT id_, index, newsettlementfee / 1000000000000, evt_block_number, evt_index
    FROM midnight.midnight_evt_setmarketsettlementfee
),

latest_settlement_fees AS (
    SELECT id_, index,
           MAX_BY(fee, ROW(evt_block_number, evt_index)) AS fee
    FROM settlement_fee_stream GROUP BY id_, index
),

settlement_fees_pivoted AS (
    SELECT
        id_,
        MAX(CASE WHEN index = UINT256 '0' THEN fee END) AS settlement_fee_cbp_0,
        MAX(CASE WHEN index = UINT256 '1' THEN fee END) AS settlement_fee_cbp_1,
        MAX(CASE WHEN index = UINT256 '2' THEN fee END) AS settlement_fee_cbp_2,
        MAX(CASE WHEN index = UINT256 '3' THEN fee END) AS settlement_fee_cbp_3,
        MAX(CASE WHEN index = UINT256 '4' THEN fee END) AS settlement_fee_cbp_4,
        MAX(CASE WHEN index = UINT256 '5' THEN fee END) AS settlement_fee_cbp_5,
        MAX(CASE WHEN index = UINT256 '6' THEN fee END) AS settlement_fee_cbp_6
    FROM latest_settlement_fees GROUP BY id_
),

-- continuousFee: last value per market
continuous_fee_stream AS (
    SELECT id_, market_continuousfee AS fee, evt_block_number, evt_index
    FROM midnight.midnight_evt_marketcreated
    UNION ALL
    SELECT id_, newcontinuousfee, evt_block_number, evt_index
    FROM midnight.midnight_evt_setmarketcontinuousfee
),

continuous_fee AS (
    SELECT id_, MAX_BY(fee, ROW(evt_block_number, evt_index)) AS continuous_fee
    FROM continuous_fee_stream GROUP BY id_
),

-- ── tickSpacing: last value per market ────────────────────────────────────────
tick_spacing_stream AS (
    SELECT id_, UINT256 '4' AS tick_spacing, evt_block_number, evt_index  -- DEFAULT_TICK_SPACING = 4
    FROM midnight.midnight_evt_marketcreated
    UNION ALL
    SELECT id_, newtickspacing, evt_block_number, evt_index
    FROM midnight.midnight_evt_setmarkettickspacing
),

tick_spacing AS (
    SELECT id_, MAX_BY(tick_spacing, ROW(evt_block_number, evt_index)) AS tick_spacing
    FROM tick_spacing_stream GROUP BY id_
)

-- ── Final join ────────────────────────────────────────────────────────────────

SELECT
    m.id_,
    COALESCE(tu.total_units,               UINT256 '0') AS total_units,
    COALESCE(lf.loss_factor,               UINT256 '0') AS loss_factor,
    COALESCE(w.withdrawable,               UINT256 '0') AS withdrawable,
    COALESCE(cfc.continuous_fee_credit,    UINT256 '0') AS continuous_fee_credit,
    tf.settlement_fee_cbp_0,
    tf.settlement_fee_cbp_1,
    tf.settlement_fee_cbp_2,
    tf.settlement_fee_cbp_3,
    tf.settlement_fee_cbp_4,
    tf.settlement_fee_cbp_5,
    tf.settlement_fee_cbp_6,
    cf.continuous_fee,
    ts.tick_spacing
FROM midnight.midnight_evt_marketcreated m
LEFT JOIN total_units            tu  ON tu.id_  = m.id_
LEFT JOIN loss_factor            lf  ON lf.id_  = m.id_
LEFT JOIN withdrawable           w   ON w.id_   = m.id_
LEFT JOIN continuous_fee_credit  cfc ON cfc.id_ = m.id_
LEFT JOIN settlement_fees_pivoted   tf  ON tf.id_  = m.id_
LEFT JOIN continuous_fee         cf  ON cf.id_  = m.id_
LEFT JOIN tick_spacing           ts  ON ts.id_  = m.id_
