// SPDX-License-Identifier: GPL-2.0-or-later

using MulDiv as MulDiv;

methods {
    function maxLif(uint256, uint256) external returns (uint256) envfree;
    function MulDiv.mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv * maxLif(lltv, cursor) <= WAD() * WAD();
}

/// Check that maxLif >= WAD
rule maxLifIsAtLeastWad(uint256 lltv, uint256 cursor) {
    assert maxLif(lltv, cursor) >= WAD();
}

/// Check that maxLif <= 2*WAD for valid cursor values
rule maxLifIsAtMostTwoWad(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require cursor <= WAD() / 2, "see LIQUIDATION_CURSOR_HIGH in ConstantsLib";
    assert maxLif(lltv, cursor) <= 2 * WAD();
}

/// Check that maxLif * lltv <= WAD * (WAD - 1) for valid cursor values
rule lifTimesLltvStrictBound(uint256 lltv, uint256 cursor) {
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv < WAD() => lltv * maxLif(lltv, cursor) <= WAD() * (WAD() - 1);
}

/// Check that mulDivUp(a, lltv, WAD()) <= mulDivUp(a, WAD(), lif)
rule mulDivLifLLTV(uint256 a, uint256 lif, uint256 lltv) {
    // lif > 0, see rule maxLifIsAtLeastWad.
    assert lltv * lif <= WAD() * WAD() => MulDiv.mulDivUp(a, lltv, WAD()) <= MulDiv.mulDivUp(a, WAD(), lif);
}
