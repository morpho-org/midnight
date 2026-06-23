// SPDX-License-Identifier: GPL-2.0-or-later

using MulDiv as MulDiv;

methods {
    function maxLif(uint256, uint256) external returns (uint256) envfree;
    function MulDiv.mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 liquidationCursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveEnabledLltv";
    require liquidationCursor <= WAD(), "enabled liquidationCursors are at most WAD, see addLiquidationCursor";
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
