// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function maxTick() external returns (uint256) envfree;
    function wExp(int256 x) external returns (uint256) envfree;
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
}

definition cvlMaxTick() returns uint256 = 5820;

definition minWExpInput() returns int256 = -20 * 10 ^ 18;

definition maxWExpInput() returns int256 = 20 * 10 ^ 18;

rule cvlMaxTickIsMaxTick() {
    assert cvlMaxTick() == maxTick();
}

// Check the casting assertions in the wExp function.
rule wExpCasting(uint256 x) {
    require x >= 0, "wExp calls wExp(-x) when x < 0";

    mathint ln2 = 693147180559945309;
    mathint offset = 322611214989459870;
    mathint q = (x + offset) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    mathint expR = 10 ^ 18 + r + secondTerm + thirdTerm;

    assert q >= 0;
    assert r < ln2 && r > -ln2;
    assert expR >= 0;
}

// wExp is only used on small bounded inputs. This domain includes the full tickToPrice range and matches
// the explicit wExp accuracy tests.
rule wExpIsIncreasing(int256 lower, int256 higher) {
    require minWExpInput() <= lower, "lower input is in range";
    require lower <= higher, "inputs are ordered";
    require higher <= maxWExpInput(), "higher input is in range";

    assert wExp(lower) <= wExp(higher);
}

rule tickToPriceIsZeroAtZero() {
    assert tickToPrice(0) == 0;
}

rule tickToPriceIsOneAtMaxTick() {
    assert tickToPrice(maxTick()) == 10 ^ 18;
}

// Tick to price is at most 1e18.
// This notably ensures that offer prices are at most 1e18.
rule tickToPriceAtMostWad(uint256 tick) {
    assert tickToPrice(tick) <= 10 ^ 18;
}
