-- Reconstructs claimableTradingFee[token] from events.
-- Take:          claimableTradingFee[loanToken] += (buyerAssets - sellerAssets)
-- ClaimTradingFee: claimableTradingFee[token]  -= amount
-- Platform: Dune Analytics (Trino SQL, native uint256)

WITH

market_loan_tokens AS (
    SELECT id_, market_loantoken AS loan_token
    FROM midnight.midnight_evt_marketcreated
),

deltas AS (
    -- Trading fee accrues on every Take: buyer pays more than seller receives
    SELECT mlt.loan_token AS token, t.buyerassets - t.sellerassets AS add_, UINT256 '0' AS sub_
    FROM midnight.midnight_evt_take t
    JOIN market_loan_tokens mlt ON mlt.id_ = t.id_

    UNION ALL

    -- Fee claimer withdraws accumulated fees
    SELECT token, UINT256 '0' AS add_, amount AS sub_
    FROM midnight.midnight_evt_claimtradingfee
)

SELECT token, SUM(add_) - SUM(sub_) AS claimable_trading_fee
FROM deltas
GROUP BY token
