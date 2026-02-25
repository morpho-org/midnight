// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    // Summaries to avoid SMT solver timeout.
    function tradingFee(bytes20, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

// absolute 1 bound --> share price (units/shares) ≤ 1 at all times
strong invariant sharePriceBelowOrEqOne(bytes20 id)
    totalShares(id) >= totalUnits(id)
{
    preserved take(uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        MorphoV2.Offer offer,
        MorphoV2.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
            if (buyerAssets != 0) {
                assert(true);
            } else if (sellerAssets != 0) {
                assert(true);
            } else if (obligationUnits != 0) {
                assert(true);
            } else {
                assert(true);
            }
        }
}



/// Liquidation without bad debt preserves virtual share price.
rule sharePricePreservedByLiquidateNoBadDebt(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes20 id
) {
    requireInvariant sharePriceBelowOrEqOne(id);

    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    // unitsAfter == unitsBefore <==> badDebt == 0 (no bad debt socialization occurred)
    assert unitsAfter == unitsBefore => (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1), "liquidation without bad debt must not decrease virtual share price";
}



/// Virtual share price = (totalUnits+1)/(totalShares+1) monotonicity.
rule sharePriceDoesNotDecrease(bytes20 id, method f) filtered {
    f -> f.selector != sig:multicall(bytes[]).selector
      && f.selector != sig:liquidate(MorphoV2.Obligation, uint256, uint256, uint256, address, bytes).selector
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

    // new lenders + new borrowers (case 1) + shares unchanged (cases 2,3 of take) => virtual share price must not decrease
        // NOTE: code uses mulDivDown in take's else-branch (obligationShares input), which cause this to fail for that case
    assert sharesAfter >= sharesBefore =>
        (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);

    // borrower exits + existing lender exits (case 4) => obligation shrinks   
        // FINDING : we have a rounding error of sharesBefore due to ceil rounding up to sharesBefore, that's why we need to include it in the inequality
    assert sharesAfter < sharesBefore =>
        (unitsAfter + 1) * (sharesBefore + 1) + sharesBefore >= (unitsBefore + 1) * (sharesAfter + 1);
}