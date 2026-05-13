// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function Utils.maxLif(uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdMarketsHaveLltvLessThanOrEqualToOne";
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv * Utils.maxLif(lltv, cursor) <= WAD() * WAD();
}

/// @dev maxLif >= WAD. Used in NoDivisionByZero.spec to prove that the nested mulDivDown divisor in maxLif is positive, without assuming it.
/// Proof: maxLif = WAD^2 / (WAD - cursor*(WAD-lltv)/WAD) and the denominator is less than WAD because the subtractions are checked to not underflow in solidity.
rule maxLifIsAtLeastWad(uint256 lltv, uint256 cursor) {
    assert Utils.maxLif(lltv, cursor) >= WAD();
}

/// @dev Strict bound for lltv < WAD: maxLif * lltv <= WAD * (WAD - 1).
/// Used in NoDivisionByZero.spec (maxLifSummary) to ensure the recovery close factor divisor
/// WAD - ceil(lif * lltv / WAD) is positive.
rule lifTimesLltvStrictBound(uint256 lltv, uint256 cursor) {
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv < WAD() => lltv * Utils.maxLif(lltv, cursor) <= WAD() * (WAD() - 1);
}
