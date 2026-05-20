// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function maxLif(uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv * maxLif(lltv, cursor) <= WAD() * WAD();
}

/// @dev maxLif >= WAD. Used in NoDivisionByZero.spec to prove that the nested mulDivDown divisor in maxLif is positive, without assuming it.
/// Proof: maxLif = WAD^2 / (WAD - cursor*(WAD-lltv)/WAD) and the denominator is less than WAD because the subtractions are checked to not underflow in solidity.
rule maxLifIsAtLeastWad(uint256 lltv, uint256 cursor) {
    assert maxLif(lltv, cursor) >= WAD();
}

/// @dev maxLif <= 2*WAD for valid cursor values. Used in NoMultiplicationOverflow.spec.
/// Proof: the denominator WAD - cursor*(WAD-lltv)/WAD is minimized at cursor=0.5e18, lltv=0,
/// giving WAD - 0.5*WAD = 0.5*WAD, so the maximum result is WAD^2/(0.5*WAD) = 2*WAD.
rule maxLifIsAtMostTwoWad(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdObligationsHaveLltvLessThanOrEqualToOne";
    require cursor <= WAD() / 2, "see LIQUIDATION_CURSOR_HIGH in ConstantsLib";
    assert maxLif(lltv, cursor) <= 2 * WAD();
}

/// @dev Strict bound for lltv < WAD: maxLif * lltv <= WAD * (WAD - 1).
/// Used in NoDivisionByZero.spec (maxLifSummary) to ensure the recovery close factor divisor
/// WAD - ceil(lif * lltv / WAD) is positive.
rule lifTimesLltvStrictBound(uint256 lltv, uint256 cursor) {
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv < WAD() => lltv * maxLif(lltv, cursor) <= WAD() * (WAD() - 1);
}
