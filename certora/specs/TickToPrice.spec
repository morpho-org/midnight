// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function lnOnePlusDelta() external returns (int256) envfree;
    function maxTick() external returns (uint256) envfree;
    function priceRoundingStep() external returns (uint256) envfree;
    function wExp(int256 x) external returns (uint256) envfree;
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
}

/// wExp properties ///

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
    assert r >= -offset && r < ln2 - offset;
    assert r < ln2 && r > -ln2;
    assert expR >= 0;
}

definition maxInput() returns int256 = assert_int256(lnOnePlusDelta() * (maxTick() / 2));

definition maxOutput() returns uint256 = 2010201770916298901946368;

rule maxOutputIsWExpOfMaxInput() {
    assert maxOutput() == wExp(maxInput());
}

rule wExpOutputBound(int256 input) {
    require -maxInput() <= input && input <= maxInput(), "sound because wExp is only called on inputs in this range";
    require wExp(input) <= wExp(maxInput()), "see rules wExpIsMonotonicOnPositiveRange and wExpIsMonotonicOnNegativeRange";
    assert wExp(input) <= maxOutput();
}

rule wExpIsMonotonicOnNegativeRange(int256 x) {
    require -maxInput() <= x && x < 0, "the positive range is proven in wExpIsMonotonicOnPositiveRange";
    int256 x1 = assert_int256(x + 1);
    assert wExp(x) <= wExp(x1);
}

// Only used as a hint for the wExpIsMonotonicOnPositiveRange rule, so it's argument type can be uint256.
function expR(uint256 x) returns mathint {
    mathint ln2 = 693147180559945309;
    mathint offset = 322611214989459870;
    mathint q = (x + offset) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    return 10 ^ 18 + r + secondTerm + thirdTerm;
}

rule expRCantGoMoreThanTimesTwo(uint256 x, uint256 y) {
    assert expR(x) <= 2 * expR(y);
}

rule wExpIsMonotonicOnPositiveRange(int256 x) {
    require 0 <= x && x < maxInput(), "the negative range is proven in wExpIsMonotonicOnNegativeRange";
    int256 x1 = assert_int256(x + 1);
    require expR(assert_uint256(x)) <= 2 * expR(assert_uint256(x1)), "by expRCantGoMoreThanTimesTwo";
    assert wExp(x) <= wExp(x1);
}

/// tickToPrice properties ///

// Useful for PriceToTick.spec
definition cvlMaxTick() returns uint256 = 5820;

rule cvlMaxTickIsMaxTick() {
    assert cvlMaxTick() == maxTick();
}

rule tickToPriceIsZeroAtZero() {
    assert tickToPrice(0) == 0;
}

rule tickToPriceIsOneAtMaxTick() {
    assert tickToPrice(maxTick()) == 10 ^ 18;
}

rule tickToPriceUsesPriceRoundingStep(uint256 tick) {
    assert tickToPrice(tick) % priceRoundingStep() == 0;
}

// Tick to price is at most 1e18.
// This notably ensures that offer prices are at most 1e18.
rule tickToPriceAtMostWad(uint256 tick) {
    assert tickToPrice(tick) <= 10 ^ 18;
}
