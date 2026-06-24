-- Reconstructs defaultSettlementFeeCbp[loanToken][index] from events.
-- SetDefaultSettlementFee emits the new value; last value per (loanToken, index) wins.
-- Platform: Dune Analytics (Trino SQL, native uint256)

SELECT loantoken AS loan_token, index, fee_cbp
FROM (
    SELECT
        loantoken,
        index,
        newsettlementfee / 1000000000000 AS fee_cbp,
        ROW_NUMBER() OVER (
            PARTITION BY loantoken, index
            ORDER BY evt_block_number DESC, evt_index DESC
        ) AS rn
    FROM midnight.midnight_evt_setdefaultsettlementfee
)
WHERE rn = 1
