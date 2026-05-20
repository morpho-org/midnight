-- Reconstructs marketState[id] from events.
-- Fields: total_units, loss_factor, withdrawable, continuous_fee_credit,
--         trading_fee_cbp_0..6, continuous_fee, tick_spacing
-- Platform: Dune Analytics (Trino SQL, native uint256)
--
-- continuousFeeCredit requires ordered processing (multiplicative Liquidate effect)
-- and is computed via a RECURSIVE CTE.

-- MAX_U128 = 2^128 - 1 = 340282366920938463463374607431768211455

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
-- Three types of event affect it (must be processed in block/log order per market):
--   UpdatePosition:     cfc += accruedFee                  (simple addition)
--   Liquidate:          cfc *= (MAX_U128 - newLF) / (MAX_U128 - oldLF)
--                       (= 0 when oldLF == MAX_U128)
--   ClaimContinuousFee: cfc -= amount                      (simple subtraction)
--
-- We merge the three event tables into a single ordered stream per market,
-- then process with a RECURSIVE CTE.

cfc_events_raw AS (
    SELECT 'U' AS etype, id_, accruedfee AS amount, CAST(NULL AS uint256) AS loss_factor,
           evt_block_number, evt_index
    FROM midnight.midnight_evt_updateposition

    UNION ALL

    SELECT 'L' AS etype, id_, CAST(NULL AS uint256), latestlossfactor,
           evt_block_number, evt_index
    FROM midnight.midnight_evt_liquidate

    UNION ALL

    SELECT 'C' AS etype, id_, amount, CAST(NULL AS uint256),
           evt_block_number, evt_index
    FROM midnight.midnight_evt_claimcontinuousfee
),

cfc_events AS (
    SELECT etype, id_, amount, loss_factor, evt_block_number, evt_index,
           ROW_NUMBER() OVER (PARTITION BY id_ ORDER BY evt_block_number, evt_index) AS n
    FROM cfc_events_raw
),

all_market_ids AS (
    SELECT DISTINCT id_ FROM midnight.midnight_evt_marketcreated
),

-- Recursive processing: seed with n=0 (initial state), then apply each event.
-- state columns: id_, n (event counter), cfc (current continuousFeeCredit), prev_lf (previous lossFactor)
cfc_state(id_, n, cfc, prev_lf) AS (
    -- Base: initial state before any events
    SELECT id_, BIGINT '0', UINT256 '0', UINT256 '0'
    FROM all_market_ids

    UNION ALL

    SELECT
        s.id_,
        s.n + 1,
        CASE e.etype
            WHEN 'U' THEN s.cfc + e.amount
            WHEN 'L' THEN
                CASE
                    WHEN s.prev_lf = UINT256 '340282366920938463463374607431768211455'
                        THEN UINT256 '0'
                    ELSE (s.cfc * (UINT256 '340282366920938463463374607431768211455' - e.loss_factor))
                         / (UINT256 '340282366920938463463374607431768211455' - s.prev_lf)
                END
            WHEN 'C' THEN s.cfc - e.amount
        END AS cfc,
        CASE e.etype WHEN 'L' THEN e.loss_factor ELSE s.prev_lf END AS prev_lf
    FROM cfc_state s
    JOIN cfc_events e ON e.id_ = s.id_ AND e.n = s.n + 1
),

continuous_fee_credit AS (
    SELECT id_, cfc AS continuous_fee_credit
    FROM (
        SELECT id_, cfc,
               ROW_NUMBER() OVER (PARTITION BY id_ ORDER BY n DESC) AS rn
        FROM cfc_state
    ) WHERE rn = 1
),

-- ── tradingFeeCbp[0..6] and continuousFee ─────────────────────────────────────
-- Initial values come from MarketCreated (= defaults at creation time).
-- Override: SetMarketTradingFee / SetMarketContinuousFee.

-- Build a combined stream of (id, index, value) for trading fee per breakpoint.
trading_fee_stream AS (
    -- MarketCreated seeds all 7 breakpoints (indices 0-6)
    SELECT id_, UINT256 '0' AS index, market_tradingfeecbp0 AS fee, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '1', market_tradingfeecbp1, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '2', market_tradingfeecbp2, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '3', market_tradingfeecbp3, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '4', market_tradingfeecbp4, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '5', market_tradingfeecbp5, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    UNION ALL SELECT id_, UINT256 '6', market_tradingfeecbp6, evt_block_number, evt_index FROM midnight.midnight_evt_marketcreated
    -- Overrides (newtradingfee is raw; divide by CBP to get stored uint16 value)
    UNION ALL
    SELECT id_, index, newtradingfee / 1000000000000, evt_block_number, evt_index
    FROM midnight.midnight_evt_setmarkettradingfee
),

latest_trading_fees AS (
    SELECT id_, index,
           MAX_BY(fee, ROW(evt_block_number, evt_index)) AS fee
    FROM trading_fee_stream GROUP BY id_, index
),

trading_fees_pivoted AS (
    SELECT
        id_,
        MAX(CASE WHEN index = UINT256 '0' THEN fee END) AS trading_fee_cbp_0,
        MAX(CASE WHEN index = UINT256 '1' THEN fee END) AS trading_fee_cbp_1,
        MAX(CASE WHEN index = UINT256 '2' THEN fee END) AS trading_fee_cbp_2,
        MAX(CASE WHEN index = UINT256 '3' THEN fee END) AS trading_fee_cbp_3,
        MAX(CASE WHEN index = UINT256 '4' THEN fee END) AS trading_fee_cbp_4,
        MAX(CASE WHEN index = UINT256 '5' THEN fee END) AS trading_fee_cbp_5,
        MAX(CASE WHEN index = UINT256 '6' THEN fee END) AS trading_fee_cbp_6
    FROM latest_trading_fees GROUP BY id_
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
    tf.trading_fee_cbp_0,
    tf.trading_fee_cbp_1,
    tf.trading_fee_cbp_2,
    tf.trading_fee_cbp_3,
    tf.trading_fee_cbp_4,
    tf.trading_fee_cbp_5,
    tf.trading_fee_cbp_6,
    cf.continuous_fee,
    ts.tick_spacing
FROM midnight.midnight_evt_marketcreated m
LEFT JOIN total_units            tu  ON tu.id_  = m.id_
LEFT JOIN loss_factor            lf  ON lf.id_  = m.id_
LEFT JOIN withdrawable           w   ON w.id_   = m.id_
LEFT JOIN continuous_fee_credit  cfc ON cfc.id_ = m.id_
LEFT JOIN trading_fees_pivoted   tf  ON tf.id_  = m.id_
LEFT JOIN continuous_fee         cf  ON cf.id_  = m.id_
LEFT JOIN tick_spacing           ts  ON ts.id_  = m.id_
