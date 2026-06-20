// SPDX-License-Identifier: GPL-2.0-or-later

using MulDiv as MulDiv;

methods {
    function maxLif(uint256, uint256) external returns (uint256) envfree;
    function MulDiv.mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 liquidationCursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require liquidationCursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv * maxLif(lltv, liquidationCursor) <= WAD() * WAD();
}

/// Check that maxLif >= WAD
rule maxLifIsAtLeastWad(uint256 lltv, uint256 liquidationCursor) {
    assert maxLif(lltv, liquidationCursor) >= WAD();
}

/// Check that maxLif <= 2*WAD for valid liquidationCursor values
rule maxLifIsAtMostTwoWad(uint256 lltv, uint256 liquidationCursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require liquidationCursor <= WAD() / 2, "see LIQUIDATION_CURSOR_HIGH in ConstantsLib";
    assert maxLif(lltv, liquidationCursor) <= 2 * WAD();
}

/// Check that maxLif * lltv <= WAD * (WAD - 1) for valid liquidationCursor values
rule lifTimesLltvStrictBound(uint256 lltv, uint256 liquidationCursor) {
    require liquidationCursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv < WAD() => lltv * maxLif(lltv, liquidationCursor) <= WAD() * (WAD() - 1);
}

/// Check that mulDivUp(a, lltv, WAD()) <= mulDivUp(a, WAD(), lif)
rule mulDivLifLLTV(uint256 a, uint256 lif, uint256 lltv) {
    // lif > 0, see rule maxLifIsAtLeastWad.
    assert lltv * lif <= WAD() * WAD() => MulDiv.mulDivUp(a, lltv, WAD()) <= MulDiv.mulDivUp(a, WAD(), lif);
}
