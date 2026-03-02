// SPDX-License-Identifier: GPL-2.0-or-later

import "SharePriceBelowOne.spec";

use invariant sharePriceBelowOrEqOne;

/// Liquidation without bad debt preserves virtual share price.
rule sharePriceDoesNotDecreaseByLiquidateNoBadDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes20 id
) {
    requireInvariant sharePriceBelowOrEqOne(id);

    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    // unitsAfter == unitsBefore <==> badDebt == 0 (no bad debt socialization occurred)
    assert unitsAfter == unitsBefore => (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}



/// Virtual share price = (totalUnits+1)/(totalShares+1) monotonicity.
rule sharePriceDoesNotDecrease(bytes20 id, method f) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
      && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector 
      && !f.isView
} {

    // We need it otherwise rounding down to 0 creates shares with no backing units
    // for withdraw +1 virtual liquidity makes exchange rate differ from actual pool ratio when totalShares > totalUnits
    requireInvariant sharePriceBelowOrEqOne(id);

    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    env e;
    calldataarg args;
    f(e, args);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    assert (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}
