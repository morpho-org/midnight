This folder contains the verification of the Midnight protocol using CVL, Certora's Verification Language.

Midnight is a fixed-rate lending protocol, see the repository [`README`](../README.md) and [`src/Midnight.sol`](../src/Midnight.sol) for the protocol itself.
The verified properties are listed below by theme, followed by the verification setup.

# Verified properties

## Core state and invariants

Global invariants on positions, markets and accounting.

- [`Midnight.spec`](specs/Midnight.spec) collects the core accounting invariants.
  Total units always equal the sum of debt plus withdrawable, a user never holds both credit and debt, and a position's pending continuous fee never exceeds its credit.
  Continuous fees stay below `MAX_CONTINUOUS_FEE` at both the default and the market level, and loss factors only ever increase, with each user's bounded by its market's.
  Rules also pin down `take`/`liquidate` input-output consistency: zero inputs give zero outputs, and `take` raises the claimable settlement fee by exactly the buyer/seller spread.
  It also shows that neither credit nor debt can grow once a market's loss factor is maxed out.
- [`BalanceEffects.spec`](specs/BalanceEffects.spec) pins down the exact credit, debt and collateral effect of every entry point.
- [`WithdrawableMonotonicity.spec`](specs/WithdrawableMonotonicity.spec) checks how withdrawable assets move: up on `repay` and `liquidate`, down by exactly the amount on `withdraw` and `claimContinuousFee`, and unchanged otherwise.
  It checks the claimable settlement fee the same way: up on `take`, down on `claimSettlementFee`, and unchanged otherwise.
- [`CreatedMarkets.spec`](specs/CreatedMarkets.spec) checks the well-formedness invariants of a created market: a non-empty collateral list, strictly sorted by token, with no zero token, and every entry with an `LLTV <= WAD` from an allowed tier and an allowed `maxLif`.
  Rules add that a market is created by the first interaction of each entry point, can only be created that way, and can never be deleted.
- [`NotCreatedMarket.spec`](specs/NotCreatedMarket.spec) checks the converse: every state field of a market that was never created is empty.
- [`LossFactor.spec`](specs/LossFactor.spec) checks that only `liquidate` changes a market's loss factor, and only when bad debt is realized (total units decrease), and that `updatePosition` syncs the user's `lastLossFactor` to the market's.
  It also checks that the loss-factor arithmetic in `updatePosition` and `liquidate` does not revert on a created market.
- [`UpdateBeforeCredit.spec`](specs/UpdateBeforeCredit.spec) checks that credit is never loaded or stored before `_updatePosition` has run for that position.

## Positions health and liquidation

Healthy positions stay healthy, and liquidations only touch liquidatable positions within the incentive bound.

- [`Healthiness.spec`](specs/Healthiness.spec) checks that no action (except oracle update) can turn a healthy borrower unhealthy.
- [`Liquidate.spec`](specs/Liquidate.spec) checks that `liquidate` can only act on a liquidatable position, leaves credit unchanged, and can only decrease the borrower's debt and the seized collateral.
- [`LiquidationProfitability.spec`](specs/LiquidationProfitability.spec) shows that the liquidation is profitable.
- [`LiquidationBoundedByLIF.spec`](specs/LiquidationBoundedByLIF.spec) checks the upper side: liquidation profit is bounded by `maxLif`.

## Offers and consumption

How offers are consumed when taken.

- [`Consume.spec`](specs/Consume.spec) checks the `consumed` mapping that tracks how much of each offer has been taken.
  Only `setConsumed` and `take` modify it, and each touches only the targeted `(user, group)` pair.
  It never decreases, a take's delta matches the units taken and stays within the offer's max, and once at the max it stops moving: a fully-consumed offer then admits only no-op takes.
- [`EmptyOffer.spec`](specs/EmptyOffer.spec) checks that taking an empty offer always reverts (so the offer tree can be padded with empty offers).
- [`Ratification.spec`](specs/Ratification.spec) checks that every successful take requires the maker to have authorized the ratifier.

## Fees

Continuous-fee accrual and settlement-fee rounding stay within their expected bounds.

- [`ContinuousFee.spec`](specs/ContinuousFee.spec) checks continuous-fee changes on `take` and `withdraw`.
  A buyer's pending fee grows by at most `floor(creditIncrease * fee * timeToMaturity / WAD)`, and a seller's pending fee decreases proportionally to the credit it loses.
  The contract's `continuousFeeCredit` grows by exactly the buyer-plus-seller accrued fees, and a `take` leaves third parties' positions and fees unchanged.
- [`SettlementFeeSpread.spec`](specs/SettlementFeeSpread.spec) checks that take rounding always favors the maker (a buyer-maker pays at most `floor(units * offerPrice / WAD)`, a seller-maker receives at least the ceil) and that the buyer/seller spread stays between `floor` and `ceil` of `units * fee / WAD`.
- [`SettlementFeeBoundaries.spec`](specs/SettlementFeeBoundaries.spec) checks that every default and per-market settlement fee stays within its per-index cap.
  A new market inherits its loan token's default fees, only the fee setter can change them, and the fee for any time-to-maturity is enclosed by its two adjacent breakpoint values.

## Authorization, roles and reverts

Who may change state, sign authorizations and hold roles, and how failures propagate.

- [`OnlyAuthorizedCanChange.spec`](specs/OnlyAuthorizedCanChange.spec) checks that an unauthorized caller cannot change a user's credit or debt (outside `liquidate` and `updatePosition`), collateral (outside `liquidate`), `consumed` (outside `take`), or `isAuthorized` entry.
  It also checks that `take` requires the caller to be the taker or authorized by them, and that `setIsAuthorized` changes only the targeted pair.
- [`EcrecoverAuthorizer.spec`](specs/EcrecoverAuthorizer.spec) checks signature-based authorization: a successful call increments only the signer's nonce, and an expired deadline, wrong nonce or reused nonce reverts.
- [`Role.spec`](specs/Role.spec) checks both liveness and access control for every role.
  The role setter and only the role setter can reassign each role.
  The fee setter can set market and default settlement and continuous fees, and once a market is created only the fee setter can change the fees.
  The tick-spacing setter and only the tick-spacing setter can set a market's tick spacing.
  The fee claimer and only the fee claimer can claim settlement and continuous fees.
- [`Reverts.spec`](specs/Reverts.spec) checks some failures reasons.
  A reverting or zero-returning collateral oracle blocks `liquidate`, `withdrawCollateral`, `isHealthy` and `take` whenever the borrower has debt.
  The liquidator (resp. enter) gate blocks liquidation (resp. credit increase and debt increase).
  A reverting `transfer`/`transferFrom` or callback (including a wrong return value) makes the calling entry point revert.

## Token transfers

Value cannot leak to unauthorized parties.

- [`Solvency.spec`](specs/Solvency.spec) checks the central solvency invariant: for every token, the contract's balance always covers the sum of collateral, withdrawable and claimable settlement fees.
- [`OnlyExplicitPayerCanLoseTokens.spec`](specs/OnlyExplicitPayerCanLoseTokens.spec) checks that tokens are only ever pulled from an explicit payer.
  In `take`, the payer can only be the `buyerCallback` if it is passed, otherwise it is either the maker for a buy offer, or `msg.sender` for a sell offer.
  In every other entry point, the payer is `msg.sender` or the corresponding callback.

## Collateral bitmap

The collateral bitmap is an optimization: no functional changes compared to the naive algorithm looping over all collaterals.

- [`CollateralBitmap.spec`](specs/CollateralBitmap.spec) checks the per-borrower collateral bitmap.
  A bit is set exactly when there is collateral at that index, and at most `MAX_COLLATERALS_PER_BORROWER` bits are ever set, which bounds the health-check and liquidation loops.
  It also proves the bitmap-optimized `isHealthy` returns the same value, and reverts no more often, than the bitmap-less implementation.
- [`Bitmap.spec`](specs/Bitmap.spec) checks the low-level 128-bit bitmap operations underpinning that abstraction: `setBit`/`clearBit` change exactly the targeted bit, `countBits` is at most 128 and positive when a bit is set, and `msb` returns the largest set bit.

## Fixed-point math

Properties of the fixed-point primitives the protocol relies on.

- [`MulDiv.spec`](specs/MulDiv.spec) proves the algebra of `mulDivDown`/`mulDivUp` that the other specs assume as axioms: correct rounding direction and tight bounds, monotonicity in each argument, behavior on zero, additivity, the down/up inverse relations, and the argument-below-denominator bound.
- [`ExactMath.spec`](specs/ExactMath.spec) checks the LIF/LLTV bounds and inequalities used elsewhere.
- [`NoDivisionByZero.spec`](specs/NoDivisionByZero.spec) checks that division by zero never occur, except for `liquidate` if the liquidated collateral is not activated or has a price of 0.
- [`NoMultiplicationOverflow.spec`](specs/NoMultiplicationOverflow.spec) checks that overflows never occur, assuming that the oracles return bounded prices.

# Verification setup

Verification is performed according to the following modeling conventions:

- loops are modeled as bounded, see the respective configuration files for the specific bounds used.
  This includes the `for` and `while` loops with the `optimistic_loop` flag, but also the hashing loops with the `optimitic_hashing` flag.
- `multicall` is removed, so each rule reasons about a single entry point.
  This is sound because `multicall` can only call functions of the current contract.
  So if all other functions respect an invariant, by induction `multicall` also respects it.
- `mulDivDown`/`mulDivUp` are replaced by ghost functions whose axioms are proven in [`MulDiv.spec`](specs/MulDiv.spec).
- bitmap operations are replaced by the ghost summaries in [`BitmapSummaries.spec`](specs/BitmapSummaries.spec), justified by [`Bitmap.spec`](specs/Bitmap.spec).
- ERC20 tokens are assumed well-behaved, see the comments in the respective files for more detail.
- unless a property is specifically about callbacks, external calls are assumed not to re-enter Midnight.

# Getting started

Install the `certora-cli` package with `pip install certora-cli`.
To verify a spec, pass its configuration file in the [`certora/confs`](confs) folder to `certoraRun`.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key, and to have `solc-0.8.34` in the PATH.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/Healthiness.conf --rule stayHealthy
```
