-- Reconstructs position[id][user] from events.
-- Fields: credit, debt, pending_fee, last_loss_factor, last_accrual
-- Collateral amounts → see position_collateral.sql
-- Platform: Dune Analytics (Trino SQL, native uint256)

WITH

-- ── Credit & debt (net position) ───────────────────────────────────────────────
-- The Take event no longer logs buyerCreditIncrease / sellerCreditDecrease, so
-- credit and debt can't be summed independently. But a position never holds credit
-- and debt at the same time: take repays debt before adding credit and consumes
-- credit before adding debt; withdraw and updatePosition only cut credit; repay and
-- liquidate only cut debt. So net = credit - debt fully determines both:
--   credit = max(0, net),  debt = max(0, -net)
-- and every net delta uses only fields still present in the events.
--
-- net up   (add_):  buyer in Take +units, Repay +units, Liquidate +(badDebt+repaidUnits)
-- net down (sub_):  seller in Take +units, Withdraw +units, UpdatePosition +creditDecrease

net_deltas AS (
    SELECT id_, IF(offerisbuy, maker, taker) AS user, units AS add_, UINT256 '0' AS sub_
    FROM midnight.midnight_evt_take
    UNION ALL
    SELECT id_, IF(offerisbuy, taker, maker) AS user, UINT256 '0' AS add_, units AS sub_
    FROM midnight.midnight_evt_take
    UNION ALL
    SELECT id_, onbehalf AS user, units, UINT256 '0'
    FROM midnight.midnight_evt_repay
    UNION ALL
    SELECT id_, borrower AS user, baddebt + repaidunits, UINT256 '0'
    FROM midnight.midnight_evt_liquidate
    UNION ALL
    SELECT id_, onbehalf AS user, UINT256 '0', units
    FROM midnight.midnight_evt_withdraw
    UNION ALL
    SELECT id_, user, UINT256 '0', creditdecrease
    FROM midnight.midnight_evt_updateposition
),

-- ── Pending fee ───────────────────────────────────────────────────────────────
-- buyer  in Take: +buyerPendingFeeIncrease  (proportional to new credit × TTM × continuousFee)
-- seller in Take: -sellerPendingFeeDecrease (proportional credit sold)
-- Withdraw: -pendingFeeDecrease             (proportional to units withdrawn)
-- UpdatePosition: -pendingFeeDecrease       (continuousFee accrued to market + slashing)

pending_fee_deltas AS (
    SELECT id_, IF(offerisbuy, maker, taker) AS user, buyerpendingfeeincrease AS add_, UINT256 '0' AS sub_
    FROM midnight.midnight_evt_take
    UNION ALL
    SELECT id_, IF(offerisbuy, taker, maker) AS user, UINT256 '0' AS add_, sellerpendingfeedecrease AS sub_
    FROM midnight.midnight_evt_take
    UNION ALL
    SELECT id_, onbehalf AS user, UINT256 '0', pendingfeedecrease
    FROM midnight.midnight_evt_withdraw
    UNION ALL
    SELECT id_, user, UINT256 '0', pendingfeedecrease
    FROM midnight.midnight_evt_updateposition
),

-- ── Aggregate the three running fields ───────────────────────────────────────

-- Keep up_ and down_ unsigned (no underflow); net = up_ - down_ at the end.
credit_debt_per_user AS (
    SELECT id_, user, SUM(add_) AS up_, SUM(sub_) AS down_
    FROM net_deltas GROUP BY id_, user
),

pending_fee_per_user AS (
    SELECT id_, user, SUM(add_) - SUM(sub_) AS pending_fee
    FROM pending_fee_deltas GROUP BY id_, user
),

-- ── lastAccrual: block_time of the most recent UpdatePosition per (id, user) ──

last_update_pos AS (
    SELECT id_, user, evt_block_number, evt_index,
           CAST(to_unixtime(evt_block_time) AS uint256) AS last_accrual
    FROM (
        SELECT id_, user, evt_block_number, evt_index, evt_block_time,
               ROW_NUMBER() OVER (
                   PARTITION BY id_, user
                   ORDER BY evt_block_number DESC, evt_index DESC
               ) AS rn
        FROM midnight.midnight_evt_updateposition
    )
    WHERE rn = 1
),

-- ── lastLossFactor: market lossFactor at the time of the last UpdatePosition ──
-- lossFactor only changes on Liquidate (via latestLossFactor field).
-- For each (id, user), find the most recent Liquidate for that market
-- that was emitted before the last UpdatePosition of that user.

last_loss_factor AS (
    SELECT
        lu.id_,
        lu.user,
        COALESCE(
            MAX_BY(liq.latestlossfactor, ROW(liq.evt_block_number, liq.evt_index)),
            UINT256 '0'
        ) AS last_loss_factor
    FROM last_update_pos lu
    LEFT JOIN midnight.midnight_evt_liquidate liq
        ON  liq.id_ = lu.id_
        AND (   liq.evt_block_number < lu.evt_block_number
             OR (liq.evt_block_number = lu.evt_block_number AND liq.evt_index < lu.evt_index))
    GROUP BY lu.id_, lu.user
),

-- ── All (id, user) pairs that ever had any activity ───────────────────────────

all_users AS (
    SELECT DISTINCT id_, user FROM net_deltas
    UNION
    SELECT DISTINCT id_, user FROM pending_fee_deltas
)

SELECT
    u.id_,
    u.user,
    IF(cd.up_ >= cd.down_, cd.up_ - cd.down_, UINT256 '0') AS credit,
    IF(cd.down_ >= cd.up_, cd.down_ - cd.up_, UINT256 '0') AS debt,
    COALESCE(p.pending_fee,       UINT256 '0') AS pending_fee,
    COALESCE(llf.last_loss_factor,UINT256 '0') AS last_loss_factor,
    COALESCE(lu.last_accrual,     UINT256 '0') AS last_accrual
FROM all_users u
LEFT JOIN credit_debt_per_user cd  ON cd.id_  = u.id_ AND cd.user  = u.user
LEFT JOIN pending_fee_per_user p   ON p.id_   = u.id_ AND p.user   = u.user
LEFT JOIN last_loss_factor     llf ON llf.id_ = u.id_ AND llf.user = u.user
LEFT JOIN last_update_pos      lu  ON lu.id_  = u.id_ AND lu.user  = u.user
