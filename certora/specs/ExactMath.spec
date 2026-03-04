// SPDX-License-Identifier: GPL-2.0-or-later

using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Midnight.maxLif(uint256, uint256) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

rule lifTimesLltvIsLessThanOrEqualToOne(uint256 lltv, uint256 cursor) {
    require lltv <= WAD(), "see rule createdObligationsHaveLltvLessThanOrEqualToOne";
    require cursor < WAD(), "see the definition of LIQUIDATION_CURSOR_LOW and LIQUIDATION_CURSOR_HIGH";
    assert lltv * maxLif(lltv, cursor) <= WAD() * WAD();
}
