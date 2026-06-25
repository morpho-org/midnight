// SPDX-License-Identifier: GPL-2.0-or-later

using MulDiv as MulDiv;

methods {
    function maxLif(uint256, uint256) external returns (uint256) envfree;
    function MulDiv.mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 liquidationCursor) {
    require lltv <= WAD(), "see rule enabledLltvIsLessThanOrEqualToOne";
    require liquidationCursor < WAD(), "see invariant enabledLiquidationCursorsIsLessThanOne";
    assert lltv * maxLif(lltv, liquidationCursor) <= WAD() * WAD();
}

rule maxLifIsAtLeastWad(uint256 lltv, uint256 liquidationCursor) {
    assert maxLif(lltv, liquidationCursor) >= WAD();
}

/// Check that mulDivUp(a, lltv, WAD()) <= mulDivUp(a, WAD(), lif)
rule mulDivLifLLTV(uint256 a, uint256 lif, uint256 lltv) {
    // lif > 0, see rule maxLifIsAtLeastWad.
    assert lltv * lif <= WAD() * WAD() => MulDiv.mulDivUp(a, lltv, WAD()) <= MulDiv.mulDivUp(a, WAD(), lif);
}

/// Check that for created markets with LLTV < WAD, the imprecision of maxRepaid computation is bounded by a factor of 1000.
/// The imprecision is the difference between maxRepaid and minimum needed to fit the requirement newDebt >= newMaxDebt.
rule maxRepaidImprecisionFactorIsAtMostOneThousand(uint256 lltv, uint256 lif) {
    require lltv < WAD(), "assume that lltv < WAD";
    require lltv == WAD() || lltv * lif <= 999 * 10 ^ 15 * WAD(), "see createdMarketsRespectMaxLifBound in CreatedMarkets.spec";
    assert WAD() * WAD() / (WAD() * WAD() - lif * lltv) <= 1000;
}
