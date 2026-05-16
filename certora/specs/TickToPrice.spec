// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function maxTick() external returns (uint256) envfree;
    function wExp(int256 x) external returns (uint256) envfree;
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
}

// Check the casting assertions in the wExp function.
rule wExpCasting(uint256 x) {
    require x >= 0, "wExp calls wExp(-x) when x < 0";
    mathint ln2 = 693147180559945309;
    mathint q = (x + ln2 / 2) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    mathint expR = 10 ^ 18 + r + secondTerm + thirdTerm;

    assert q >= 0;
    assert r < ln2 && r > -ln2;
    assert expR >= 0;
}

rule wExpIsMonotonic(int256 x1, int256 x2) {
    assert x1 < x2 => wExp(x1) <= wExp(x2);
}

// Tick to price is at most 1e18.
// This notably ensures that offer prices are at most 1e18.
rule tickToPriceAtMostWad(uint256 tick) {
    assert tickToPrice(tick) <= 10 ^ 18;
}

rule tickToPriceIsMonotonic(uint256 tick1, uint256 tick2) {
    require 0 <= tick1 && tick1 <= maxTick(), "sound because we call tickToPrice on tick1";
    require 0 <= tick2 && tick2 <= maxTick(), "sound because we call tickToPrice on tick2";

    require tick1 < tick2, "assume tick are ordered to begin with, then show that their images are also ordered";
    require wExp(assert_int256(tick1)) <= wExp(assert_int256(tick2)), "see rule wExpIsMonotonic";
    assert tickToPrice(tick1) <= tickToPrice(tick2);
}

rule tickToPriceIsZeroAtZero() {
    assert tickToPrice(0) == 0;
}
