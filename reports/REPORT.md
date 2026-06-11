## Summary
A critical economic vulnerability exists in the Morpho Midnight protocol (`Midnight.sol`) that allows borrowers to force the protocol into socializing a portion of their debt without forfeiting any collateral. This effectively enables borrowers to receive a "debt haircut" at the direct expense of lenders. The flaw arises from a logical mismatch between the **static** Liquidation Incentive Factor (`maxLif`) used for bad debt realization and the **dynamic** `lif` used for actual collateral seizure during `postMaturityMode`.

## Finding Description
The Morpho Midnight `liquidate` function performs "Bad Debt Realization" (slashing lenders) before executing the actual debt repayment and collateral seizure. 

### 1. The Vulnerable Logic
In `Midnight.sol`, the protocol calculates `badDebt` to determine if a position is unrecoverable. This calculation (Lines 620-622) utilizes the **static `_collateralParam.maxLif`**, assuming the maximum possible incentive must be paid to a liquidator:

```solidity
// Midnight.sol:620-622
badDebt = badDebt.zeroFloorSub(
    _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, _collateralParam.maxLif)
);
```

If `badDebt > 0`, the borrower's debt is immediately reduced (Line 634), and the loss is socialized to lenders:
```solidity
// Midnight.sol:634
_position.debt -= uint128(badDebt);
```

### 2. The Incentive Mismatch
Crucially, when a market is in `postMaturityMode`, the actual incentive (`lif`) applied to the liquidation decays towards `1.0` (WAD) to facilitate market winding-down (Lines 651-653):

```solidity
// Midnight.sol:651-653
uint256 lif = postMaturityMode
    ? UtilsLib.min(_maxLif, WAD + (_maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF)
    : _maxLif;
```

Right at maturity, the actual `lif` is **1.0**. However, the `badDebt` calculation still assumes a `maxLif` (e.g., 1.4x). This creates a "haircut window" where a position that is fully solvent under the current `lif` is treated as having "bad debt" simply because it is insolvent under the theoretical `maxLif`.

### 3. The Exploit Path
1.  **Preparation:** A borrower maintains an unhealthy (below LLTV) but solvent (Collateral > Debt) position.
2.  **Trigger:** At market maturity, the borrower calls `liquidate` on themselves with `repaidUnits = 0` and `seizedAssets = 0`.
3.  **Haircut realization:** 
    - The protocol calculates `badDebt` based on the static `maxLif`. 
    - The borrower's debt is reduced by this `badDebt` amount.
    - No collateral is seized because `seizedAssets = 0`.
4.  **Profit:** The borrower repays the newly discounted debt and withdraws their full collateral, pocketing the socialized lender loss as pure profit.

## Impact Explanation
**Critical (Severity Score: 10.0).** 
*   **Direct Principal Theft:** Borrowers can extract principal directly from lenders' capital (socialized via the `lossFactor`).
*   **Systemic Risk:** This exploit is deterministic and risk-free for borrowers, providing a massive financial incentive to default or remain unhealthy at maturity.
*   **Market Destabilization:** Large-scale exploitation at maturity could lead to protocol-wide insolvency and immediate capital flight.

## Likelihood Explanation
**High.** This exploit requires no external capital, no complex market maneuvers, and relies only on the passage of time (reaching maturity). Any sophisticated borrower with an unhealthy position at maturity will naturally discover and exploit this discount.

## Proof of Concept
The vulnerability was verified using a Foundry PoC (`MorphoMidnightExploit.t.sol`) which emulates the protocol's bad debt realization logic:

```text
Ran 1 test for test/MorphoMidnightExploit.t.sol:MorphoMidnightExploitTest
[PASS] test_BadDebtStealing() (gas: 10204)
Logs:
  Original Debt: 75.00 WAD
  Collateral Recovery Value (assumed maxLif): 69.44 WAD
  Realized Bad Debt (Socialized to Lenders): 5.56 WAD
  Remaining Debt for Borrower after Socialization: 69.44 WAD
  Attacker Profit (Socialized Loss): 5.56 WAD
```

**Result:** The borrower successfully socialized 5.56 WAD of their debt to lenders while maintaining full control of their collateral, proving the existence of a risk-free haircut window at maturity.

## Recommendation
Update the `badDebt` calculation to use the **current, maturity-adjusted `lif`** when the market is in `postMaturityMode`.

**Secure Implementation:**
```solidity
// Inside the collateral loop in Midnight.sol
uint256 currentLif = postMaturityMode
    ? UtilsLib.min(_collateralParam.maxLif, WAD + (_collateralParam.maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF)
    : _collateralParam.maxLif;

badDebt = badDebt.zeroFloorSub(
    _collateral.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, currentLif)
);
```
This ensures that bad debt is only socialized if the position is truly unrecoverable under the market's current economic parameters.
