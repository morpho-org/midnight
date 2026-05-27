This folder contains the verification of the Midnight protocol using CVL, Certora's Verification Language.

Midnight is a fixed-rate lending protocol, see the repository [`README`](../README.md) and [`src/Midnight.sol`](../src/Midnight.sol) for the protocol itself.
The verified properties are listed below by theme, followed by the verification setup.

# Verified properties

## Core state and invariants

Global invariants on positions, markets and accounting.

- [`Midnight.spec`](specs/Midnight.spec) checks core invariants: `take`/`liquidate` input-output consistency, monotonicity of the loss factor, that a user never has both credit and debt, and that there is no continuous fee without credit.
- [`BalanceEffects.spec`](specs/BalanceEffects.spec) checks the exact credit/debt/collateral effect of each entry point, and that the other functions leave them unchanged.
- [`CreatedMarkets.spec`](specs/CreatedMarkets.spec) checks the invariants of a created market (non-empty sorted collaterals, valid LLTV tier and `maxLif`) and that markets are created on first interaction and never deleted.
- [`NotCreatedMarket.spec`](specs/NotCreatedMarket.spec) checks that every state field of a non-created market is empty.
- [`LossFactor.spec`](specs/LossFactor.spec) checks that only `liquidate` changes a market's loss factor (and only when bad debt is realized), and that `updatePosition` syncs the user's `lastLossFactor`.
- [`UpdateBeforeCredit.spec`](specs/UpdateBeforeCredit.spec) checks that credit is never loaded or stored before `_updatePosition` runs.

## Positions health and liquidation

Healthy positions stay healthy, and liquidations only touch liquidatable positions within the incentive bound.

- [`Healthiness.spec`](specs/Healthiness.spec) checks that, at constant price, no action can turn a healthy borrower unhealthy.
- [`Liquidate.spec`](specs/Liquidate.spec) checks that `liquidate` only affects liquidatable positions and can only decrease the borrower's debt and collateral.
- [`LiquidationProfitability.spec`](specs/LiquidationProfitability.spec) checks the liquidation incentive factor: `lif >= WAD` (the liquidator never loses) and `lif == maxLif` on the unhealthy or post-maturity path.
- [`LiquidationBoundedByLIF.spec`](specs/LiquidationBoundedByLIF.spec) checks that liquidation profit is bounded by `maxLif`, for both the `repaidUnits` and `seizedAssets` inputs.

## Offers and consumption

How offers are consumed when taken.

- [`Consume.spec`](specs/Consume.spec) checks the `consumed` mapping: only `setConsumed` and `take` change it, it never decreases, and a take's delta matches the units taken up to the offer's max.
- [`EmptyOffer.spec`](specs/EmptyOffer.spec) checks that taking an empty offer always reverts (so the offer tree can be padded with empty offers).
- [`Ratification.spec`](specs/Ratification.spec) checks that every take requires the maker to have authorized the ratifier, and that `address(0)` can never be the maker.

## Fees

Continuous-fee accrual and trading-fee rounding stay within their expected bounds.

- [`ContinuousFee.spec`](specs/ContinuousFee.spec) checks continuous-fee accrual: buyer/seller pending fees move by the expected rounded amounts and `continuousFeeCredit` grows by exactly the accrued sum, without affecting third parties.
- [`TradingFeeSpread.spec`](specs/TradingFeeSpread.spec) checks that take rounding always favors the maker and that the buyer/seller spread is bounded by the trading fee.
- [`TradingFeeBoundaries.spec`](specs/TradingFeeBoundaries.spec) checks that trading fees stay within their per-index cap, new markets inherit the loan token's defaults, and the fee is enclosed by its adjacent breakpoints for any time-to-maturity.
- [`WithdrawableMonotonicity.spec`](specs/WithdrawableMonotonicity.spec) checks how withdrawable assets and claimable trading fees move: up on repay/liquidate/take, down by exactly the amount on withdraw/claim, unchanged otherwise.

## Authorization, roles and reverts

Who may change state, sign authorizations and hold roles, and how failures propagate.

- [`OnlyAuthorizedCanChange.spec`](specs/OnlyAuthorizedCanChange.spec) checks that an unauthorized caller cannot change a user's credit, debt, collateral, `consumed` or authorization (outside the `liquidate`/`updatePosition`/`take` paths, covered separately).
- [`EcrecoverAuthorizer.spec`](specs/EcrecoverAuthorizer.spec) checks signature-based authorization: the nonce increments on success, and an expired deadline, wrong nonce or reused nonce reverts.
- [`Role.spec`](specs/Role.spec) checks role management: each role setter can update its own parameter, and only the matching role can change role assignments, fees, tick spacing or claim fees.
- [`Reverts.spec`](specs/Reverts.spec) checks failure propagation: oracle reverts/zeros, blocking gates, and reverting token transfers or callbacks all make the relevant entry points revert.

## Token value safety

Value cannot leak to unauthorized parties.

- [`Solvency.spec`](specs/Solvency.spec) checks that the contract balance always covers collateral + withdrawable + claimable fees minus outstanding flash loans, and that flash loans are repaid by the end of the transaction.
- [`OnlyExplicitPayerCanLoseTokens.spec`](specs/OnlyExplicitPayerCanLoseTokens.spec) checks that tokens can only be pulled from an explicit payer — the caller, or a callback that returned the success value — never an arbitrary account.

## Collateral bitmap

The per-borrower collateral bitmap is consistent and bounded.

- [`CollateralBitmap.spec`](specs/CollateralBitmap.spec) checks that a collateral bit is set exactly when collateral exists at that index, bounds the number of activated collaterals, and proves the bitmap-optimized `isHealthy` matches the bitmap-less one.
- [`Bitmap.spec`](specs/Bitmap.spec) checks the low-level 128-bit bitmap operations (`setBit`, `clearBit`, `countBits`, `msb`).

## Fixed-point math

Correctness and safety of the fixed-point primitives the protocol relies on.

- [`MulDiv.spec`](specs/MulDiv.spec) checks `mulDivDown`/`mulDivUp` correctness: rounding direction, monotonicity, tight bounds and composition.
- [`ExactMath.spec`](specs/ExactMath.spec) checks the LIF/LLTV bounds (`lif * lltv <= WAD^2` and `WAD <= maxLif <= 2 * WAD`).
- [`NoDivisionByZero.spec`](specs/NoDivisionByZero.spec) checks that no reachable protocol path divides by zero.
- [`NoMultiplicationOverflow.spec`](specs/NoMultiplicationOverflow.spec) checks that the fixed-point multiplications never overflow, given a bounded oracle price.

# Verification setup

The [`certora/confs`](confs) folder holds one configuration file per verified spec, named to match the spec.
There are 29: every spec has one except the imported-only [`BitmapSummaries.spec`](specs/BitmapSummaries.spec).
Each points `certoraRun` at the spec and the contract under verification — usually [`src/Midnight.sol`](../src/Midnight.sol), sometimes another source contract or a helper wrapper.
They all share the compiler and prover settings (`solc-0.8.34`, `via_ir`, EVM `osaka`).

The [`certora/helpers`](helpers) folder holds the auxiliary contracts the specs link against:

- [`Utils.sol`](helpers/Utils.sol) exposes `UtilsLib` bitmap operations and protocol constants to the specs.
- [`MulDiv.sol`](helpers/MulDiv.sol) exposes `UtilsLib.mulDivDown`/`mulDivUp` for `MulDiv.spec`.
- [`MidnightWrapper.sol`](helpers/MidnightWrapper.sol) extends `Midnight` with `isHealthyNoBitmap`, the bitmap-less health check used to validate the bitmap optimization.
- [`FlashLiquidateCallback.sol`](helpers/FlashLiquidateCallback.sol) is a mock flash-loan / repay / liquidate callback used to model those callbacks.
- [`Havoc.sol`](helpers/Havoc.sol) is a minimal contract whose `havocAll()` lets a callback havoc all state, modeling arbitrary re-entrant behavior.

## Modeling conventions

All specs share a few modeling conventions:

- `multicall` is removed, so each rule reasons about a single entry point.
- `mulDivDown`/`mulDivUp` are replaced by ghost functions whose axioms are proven in [`MulDiv.spec`](specs/MulDiv.spec).
- bitmap operations are replaced by the ghost summaries in [`BitmapSummaries.spec`](specs/BitmapSummaries.spec) (justified by [`Bitmap.spec`](specs/Bitmap.spec)), which other specs import and which is therefore not verified on its own.
- ERC20 tokens are assumed well-behaved: no fee-on-transfer, rebasing, blacklisting or transfer limits.
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
