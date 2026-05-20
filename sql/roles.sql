-- Reconstructs the four admin role addresses from events.
-- roleSetter:        set in Constructor, then overridden by SetRoleSetter
-- feeSetter:         set by SetFeeSetter (initial = address(0))
-- feeClaimer:        set by SetFeeClaimer (initial = address(0))
-- tickSpacingSetter: set by SetTickSpacingSetter (initial = address(0))
-- Platform: Dune Analytics (Trino SQL)

WITH

role_setter_stream AS (
    SELECT rolesetter AS addr, evt_block_number, evt_index FROM midnight.midnight_evt_constructor
    UNION ALL
    SELECT rolesetter, evt_block_number, evt_index FROM midnight.midnight_evt_setrolesetter
),

fee_setter_stream AS (
    SELECT feesetter AS addr, evt_block_number, evt_index FROM midnight.midnight_evt_setfeesetter
),

fee_claimer_stream AS (
    SELECT feeclaimer AS addr, evt_block_number, evt_index FROM midnight.midnight_evt_setfeeclaimer
),

tick_spacing_setter_stream AS (
    SELECT tickspacingsetter AS addr, evt_block_number, evt_index FROM midnight.midnight_evt_settickspacingsetter
)

SELECT
    (SELECT MAX_BY(addr, ROW(evt_block_number, evt_index)) FROM role_setter_stream)         AS role_setter,
    (SELECT MAX_BY(addr, ROW(evt_block_number, evt_index)) FROM fee_setter_stream)          AS fee_setter,
    (SELECT MAX_BY(addr, ROW(evt_block_number, evt_index)) FROM fee_claimer_stream)         AS fee_claimer,
    (SELECT MAX_BY(addr, ROW(evt_block_number, evt_index)) FROM tick_spacing_setter_stream) AS tick_spacing_setter
