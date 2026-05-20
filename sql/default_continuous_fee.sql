-- Reconstructs defaultContinuousFee[loanToken] from events.
-- SetDefaultContinuousFee emits the new value; last value per loanToken wins.
-- Platform: Dune Analytics (Trino SQL, native uint256)

SELECT loantoken AS loan_token, fee
FROM (
    SELECT
        loantoken,
        newcontinuousfee AS fee,
        ROW_NUMBER() OVER (
            PARTITION BY loantoken
            ORDER BY evt_block_number DESC, evt_index DESC
        ) AS rn
    FROM midnight.midnight_evt_setdefaultcontinuousfee
)
WHERE rn = 1
