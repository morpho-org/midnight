-- =============================================================================
-- Midnight Protocol: State Reconstruction from Events
-- =============================================================================
--
-- Every on-chain state variable can be recomputed from indexed events.
--
-- Conventions:
--   - Tables: midnight.<snake_case_event_name>
--   - Every table carries: block_number, log_index, block_timestamp
--   - Query parameters: $id, $user, $index, $loan_token, $group, $collateral_token, ...
--   - PostgreSQL syntax
--   - PASSIVE_FEE_RECIPIENT = address(uint160(uint256(keccak256("passive fee recipient"))))
--
-- Prerequisite helper table:
--   midnight.obligation_collaterals(id_, collateral_index, token)
--   Derived from the Obligation struct in ObligationCreated events.
--   Maps (id_, token) <-> (id_, collateral_index).

-- =============================================================================
-- 1. SINGLETON STATE VARIABLES
-- =============================================================================

-- owner
SELECT COALESCE(
  (SELECT owner FROM midnight.set_owner ORDER BY block_number DESC, log_index DESC LIMIT 1),
  (SELECT owner FROM midnight.constructor LIMIT 1)
) AS owner;

-- feeSetter
SELECT COALESCE(
  (SELECT fee_setter FROM midnight.set_fee_setter ORDER BY block_number DESC, log_index DESC LIMIT 1),
  '0x0000000000000000000000000000000000000000'
) AS fee_setter;

-- feeRecipient
SELECT COALESCE(
  (SELECT fee_recipient FROM midnight.set_fee_recipient ORDER BY block_number DESC, log_index DESC LIMIT 1),
  '0x0000000000000000000000000000000000000000'
) AS fee_recipient;

-- =============================================================================
-- 2. SIMPLE MAPPING STATE VARIABLES
-- =============================================================================

-- defaultTradingFees[$loan_token][$index]
SELECT COALESCE(
  (SELECT new_trading_fee
   FROM midnight.set_default_trading_fee
   WHERE loan_token = $loan_token AND "index" = $index
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  0
) AS default_trading_fee;

-- defaultContinuousFee[$loan_token]
SELECT COALESCE(
  (SELECT new_continuous_fee
   FROM midnight.set_default_continuous_fee
   WHERE loan_token = $loan_token
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  0
) AS default_continuous_fee;

-- session[$user]
SELECT COALESCE(
  (SELECT session
   FROM midnight.shuffle_session
   WHERE on_behalf = $user
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  '\x0000000000000000000000000000000000000000000000000000000000000000'
) AS session;

-- isAuthorized[$authorizer][$authorized]
SELECT COALESCE(
  (SELECT new_is_authorized
   FROM midnight.set_is_authorized
   WHERE on_behalf = $authorizer AND authorized = $authorized
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  false
) AS is_authorized;

-- consumed[$user][$group]
-- Set to an absolute value by both Take (for maker) and SetConsumed.
-- The latest event wins.
SELECT COALESCE(
  (SELECT amount FROM (
    SELECT consumed AS amount, block_number, log_index
    FROM midnight.take
    WHERE maker = $user AND "group" = $group

    UNION ALL

    SELECT amount, block_number, log_index
    FROM midnight.set_consumed
    WHERE on_behalf = $user AND "group" = $group
  ) all_events
  ORDER BY block_number DESC, log_index DESC
  LIMIT 1),
  0
) AS consumed;

-- =============================================================================
-- 3. OBLIGATION STATE
-- =============================================================================

-- obligationState[$id].created
SELECT EXISTS(
  SELECT 1 FROM midnight.obligation_created WHERE id_ = $id
) AS created;

-- obligationState[$id].fees[$index]
-- Initialized from defaultTradingFees[loanToken] at creation, then overridable.
WITH creation AS (
  SELECT block_number, log_index, obligation_loan_token
  FROM midnight.obligation_created
  WHERE id_ = $id
)
SELECT COALESCE(
  (SELECT new_trading_fee
   FROM midnight.set_obligation_trading_fee
   WHERE id_ = $id AND "index" = $index
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  (SELECT sdt.new_trading_fee
   FROM midnight.set_default_trading_fee sdt, creation c
   WHERE sdt.loan_token = c.obligation_loan_token
     AND sdt."index" = $index
     AND (sdt.block_number, sdt.log_index) < (c.block_number, c.log_index)
   ORDER BY sdt.block_number DESC, sdt.log_index DESC
   LIMIT 1),
  0
) AS trading_fee;

-- obligationState[$id].continuousFee
-- Same pattern: override > default-at-creation > 0.
WITH creation AS (
  SELECT block_number, log_index, obligation_loan_token
  FROM midnight.obligation_created
  WHERE id_ = $id
)
SELECT COALESCE(
  (SELECT new_continuous_fee
   FROM midnight.set_obligation_continuous_fee
   WHERE id_ = $id
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  (SELECT sdc.new_continuous_fee
   FROM midnight.set_default_continuous_fee sdc, creation c
   WHERE sdc.loan_token = c.obligation_loan_token
     AND (sdc.block_number, sdc.log_index) < (c.block_number, c.log_index)
   ORDER BY sdc.block_number DESC, sdc.log_index DESC
   LIMIT 1),
  0
) AS continuous_fee;

-- obligationState[$id].totalUnits
-- Deltas from Take, Withdraw, and Liquidate (bad debt).
SELECT COALESCE(SUM(delta), 0) AS total_units
FROM (
  SELECT (buyer_credit_increase - seller_credit_decrease)::numeric AS delta
  FROM midnight.take WHERE id_ = $id

  UNION ALL

  SELECT -units::numeric FROM midnight.withdraw WHERE id_ = $id

  UNION ALL

  SELECT -bad_debt::numeric FROM midnight.liquidate WHERE id_ = $id
) d;

-- obligationState[$id].lossIndex
-- Absolute value from the latest Liquidate event, or 0.
SELECT COALESCE(
  (SELECT latest_loss_index
   FROM midnight.liquidate
   WHERE id_ = $id
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  0
) AS loss_index;

-- obligationState[$id].withdrawable
-- Deltas from Repay (+units), Withdraw (-units), Liquidate (+repaidUnits).
SELECT COALESCE(SUM(delta), 0) AS withdrawable
FROM (
  SELECT units::numeric AS delta FROM midnight.repay WHERE id_ = $id

  UNION ALL

  SELECT -units::numeric FROM midnight.withdraw WHERE id_ = $id

  UNION ALL

  SELECT repaid_units::numeric FROM midnight.liquidate WHERE id_ = $id
) d;

-- =============================================================================
-- 4. POSITION STATE
-- =============================================================================

-- position[$id][$user].credit
-- Sources:
--   UpdatePosition(id_, user)      : -creditDecrease
--   UpdatePosition(id_, any_user)  : +accruedFee  (only for PASSIVE_FEE_RECIPIENT)
--   Take  (as buyer)               : +buyerCreditIncrease
--   Take  (as seller)              : -sellerCreditDecrease
--   Withdraw                       : -units
SELECT COALESCE(SUM(delta), 0) AS credit
FROM (
  -- UpdatePosition: user's credit decreases
  SELECT -credit_decrease::numeric AS delta
  FROM midnight.update_position
  WHERE id_ = $id AND "user" = $user

  UNION ALL

  -- UpdatePosition: PASSIVE_FEE_RECIPIENT collects accrued fees from ALL users
  -- This subquery contributes rows only when $user is the fee recipient.
  SELECT accrued_fee::numeric
  FROM midnight.update_position
  WHERE id_ = $id AND $user = $PASSIVE_FEE_RECIPIENT

  UNION ALL

  -- Take: buyer credit increases
  SELECT buyer_credit_increase::numeric
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN maker ELSE taker END = $user

  UNION ALL

  -- Take: seller credit decreases
  SELECT -seller_credit_decrease::numeric
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN taker ELSE maker END = $user

  UNION ALL

  -- Withdraw
  SELECT -units::numeric
  FROM midnight.withdraw
  WHERE id_ = $id AND on_behalf = $user
) d;

-- position[$id][$user].pendingFee
-- Sources:
--   UpdatePosition  : -pendingFeeDecrease
--   Take (as buyer) : +buyerPendingFeeIncrease
--   Take (as seller): -sellerPendingFeeDecrease
--   Withdraw        : -pendingFeeDecrease
SELECT COALESCE(SUM(delta), 0) AS pending_fee
FROM (
  SELECT -pending_fee_decrease::numeric AS delta
  FROM midnight.update_position
  WHERE id_ = $id AND "user" = $user

  UNION ALL

  SELECT buyer_pending_fee_increase::numeric
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN maker ELSE taker END = $user

  UNION ALL

  SELECT -seller_pending_fee_decrease::numeric
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN taker ELSE maker END = $user

  UNION ALL

  SELECT -pending_fee_decrease::numeric
  FROM midnight.withdraw
  WHERE id_ = $id AND on_behalf = $user
) d;

-- position[$id][$user].debt
-- Sources:
--   Take (as buyer)  : -(units - buyerCreditIncrease)   i.e. debt repaid
--   Take (as seller) : +(units - sellerCreditDecrease)  i.e. debt taken on
--   Repay            : -units
--   Liquidate        : -(badDebt + repaidUnits)
SELECT COALESCE(SUM(delta), 0) AS debt
FROM (
  SELECT -(units - buyer_credit_increase)::numeric AS delta
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN maker ELSE taker END = $user

  UNION ALL

  SELECT (units - seller_credit_decrease)::numeric
  FROM midnight.take
  WHERE id_ = $id
    AND CASE WHEN offer_is_buy THEN taker ELSE maker END = $user

  UNION ALL

  SELECT -units::numeric
  FROM midnight.repay
  WHERE id_ = $id AND on_behalf = $user

  UNION ALL

  SELECT -(bad_debt + repaid_units)::numeric
  FROM midnight.liquidate
  WHERE id_ = $id AND borrower = $user
) d;

-- position[$id][$user].collateral[$collateral_index]
-- Sources:
--   SupplyCollateral   (by token)  : +assets
--   WithdrawCollateral (by token)  : -assets
--   Liquidate          (by index)  : -seizedAssets
-- SupplyCollateral and WithdrawCollateral use token address; Liquidate uses index.
-- We join through midnight.obligation_collaterals to unify them.
WITH collat AS (
  SELECT token
  FROM midnight.obligation_collaterals
  WHERE id_ = $id AND collateral_index = $collateral_index
)
SELECT COALESCE(SUM(delta), 0) AS collateral
FROM (
  SELECT assets::numeric AS delta
  FROM midnight.supply_collateral sc, collat c
  WHERE sc.id_ = $id AND sc.on_behalf = $user AND sc.collateral = c.token

  UNION ALL

  SELECT -assets::numeric
  FROM midnight.withdraw_collateral wc, collat c
  WHERE wc.id_ = $id AND wc.on_behalf = $user AND wc.collateral = c.token

  UNION ALL

  SELECT -seized_assets::numeric
  FROM midnight.liquidate
  WHERE id_ = $id AND borrower = $user AND collateral_index = $collateral_index
) d;

-- position[$id][$user].activatedCollaterals
-- A bitmap where bit i is set iff collateral[i] > 0.
-- Derived by checking which collateral indices have a positive balance.
WITH collateral_balances AS (
  SELECT oc.collateral_index, COALESCE(SUM(delta), 0) AS balance
  FROM midnight.obligation_collaterals oc
  LEFT JOIN LATERAL (
    SELECT assets::numeric AS delta
    FROM midnight.supply_collateral sc
    WHERE sc.id_ = $id AND sc.on_behalf = $user AND sc.collateral = oc.token

    UNION ALL

    SELECT -assets::numeric
    FROM midnight.withdraw_collateral wc
    WHERE wc.id_ = $id AND wc.on_behalf = $user AND wc.collateral = oc.token

    UNION ALL

    SELECT -seized_assets::numeric
    FROM midnight.liquidate l
    WHERE l.id_ = $id AND l.borrower = $user AND l.collateral_index = oc.collateral_index
  ) d ON true
  WHERE oc.id_ = $id
  GROUP BY oc.collateral_index
)
SELECT COALESCE(SUM(1::numeric << collateral_index), 0)::numeric AS activated_collaterals
FROM collateral_balances
WHERE balance > 0;

-- position[$id][$user].lossIndex
-- Set to the obligation's lossIndex at the time of the user's most recent UpdatePosition.
-- If no UpdatePosition ever occurred for this (id, user), the value is 0.
WITH last_update AS (
  SELECT block_number, log_index
  FROM midnight.update_position
  WHERE id_ = $id AND "user" = $user
  ORDER BY block_number DESC, log_index DESC
  LIMIT 1
)
SELECT COALESCE(
  (SELECT COALESCE(
    (SELECT l.latest_loss_index
     FROM midnight.liquidate l, last_update lu
     WHERE l.id_ = $id
       AND (l.block_number, l.log_index) <= (lu.block_number, lu.log_index)
     ORDER BY l.block_number DESC, l.log_index DESC
     LIMIT 1),
    0)
  FROM last_update),
  0
) AS loss_index;

-- position[$id][$user].lastAccrual
-- Set to block.timestamp at the user's most recent UpdatePosition.
-- 0 if no UpdatePosition ever occurred.
SELECT COALESCE(
  (SELECT block_timestamp
   FROM midnight.update_position
   WHERE id_ = $id AND "user" = $user
   ORDER BY block_number DESC, log_index DESC
   LIMIT 1),
  0
) AS last_accrual;
