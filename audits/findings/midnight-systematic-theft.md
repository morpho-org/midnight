# Final Vulnerability Report: Systematic Theft from Lenders via Manipulated Bad Debt Realization

## Severity: High/Critical
This vulnerability allows borrowers to directly steal from lenders by exploiting an inconsistency in how "bad debt" is socialized compared to how liquidation penalties are applied.

## Summary
In `Midnight.sol`, the protocol socializes "bad debt" when a position is deemed unrecoverable. This calculation relies on a static `maxLif` (Liquidation Incentive Factor). However, after a market's maturity, the actual incentive factor (`lif`) applied to liquidators is dynamically reduced, eventually reaching `1.0`. 

By triggering a liquidation on themselves at maturity, a solvent but unhealthy borrower can force the protocol to "forgive" a portion of their debt as "bad debt", despite the fact that the debt is fully covered by collateral under the current maturity-adjusted parameters. This forgiven debt is a direct loss to the market's lenders.

## Vulnerability Details
The `liquidate` function calculates `badDebt` using the static `_collateralParam.maxLif` regardless of the liquidation mode:

```solidity
// Midnight.sol L635-L637
badDebt = badDebt.zeroFloorSub(
    _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
);
```

When `badDebt > 0`, the borrower's debt is reduced and lenders are slashed:

```solidity
// Midnight.sol L647-L661
if (badDebt > 0) {
    _position.debt -= uint128(badDebt);
    // ... update market lossFactor (slashing lenders) ...
}
```

However, in `postMaturityMode`, the actual penalty used for seizing assets is much lower:

```solidity
// Midnight.sol L665-L667
uint256 lif = postMaturityMode
    ? UtilsLib.min(_maxLif, WAD + (_maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF)
    : _maxLif;
```

Right at maturity, `lif` is `1.0` (WAD). But the `badDebt` logic still assumes the liquidator will take `maxLif` (e.g., 1.1x or 1.4x). This mismatch creates a gap where debt is "forgiven" by the protocol even though it could be fully repaid.

## Exploit Scenario
1. **Initial State**:
   - Market LLTV = 0.385, maxLif = 1.44.
   - Borrower has 100 WAD collateral (Value = 100) and 75 WAD debt.
   - Borrower is **Unhealthy** (75 > 38.5) but **Solvent** (75 < 100).
2. **Execution**:
   - At `block.timestamp == maturity + 1`, the borrower calls `liquidate(..., seizedAssets=0, repaidUnits=0, postMaturityMode=true)` on themselves.
3. **Outcome**:
   - Protocol calculates `badDebt = 75 - (100 / 1.44) = 75 - 69.44 = 5.56 WAD`.
   - Borrower's debt is reduced to 69.44 WAD. Lenders lose 5.56 WAD.
   - Borrower calls `repay(69.44)` and `withdrawCollateral(100)`.
   - **Net Profit**: The borrower spent 69.44 WAD to clear 75 WAD of initial debt, pocketing **5.56 WAD** at the expense of lenders.

## Impact
- Direct theft of lender funds.
- Systematic drain of protocol liquidity by malicious borrowers.
- Inversion of incentives: borrowers are rewarded for failing to repay before maturity.

## Recommendation
The `badDebt` calculation must use the current, maturity-adjusted `lif` instead of the static `maxLif` when in `postMaturityMode`.

### Proposed Fix
```solidity
<<<<
            badDebt = badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
            );
====
            uint256 lif_current = postMaturityMode
                ? UtilsLib.min(_collateralParam.maxLif, WAD + (_collateralParam.maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF)
                : _collateralParam.maxLif;
            badDebt = badDebt.zeroFloorSub(
                _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif_current)
            );
>>>>
```
Note: Since `badDebt` is calculated in a loop before `lif` is determined for the specific `collateralIndex`, the logic for `lif` should be replicated or refactored to be accessible inside the loop.
