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

definition maxOutput() returns uint256 = 20134595243400876315901952;

rule maxOutputIsWExpOfMaxInput() {
    assert maxOutput() == wExp(maxInput());
}

rule wExpOutputBound(int256 input) {
    require -maxInput() <= input && input <= maxInput(), "sound because wExp is only called on inputs in this range";
    require wExp(input) <= wExp(maxInput()), "see rules wExpIsMonotonicOnPositiveRangeWhenQStays/WhenQJumps and wExpIsMonotonicOnNegativeRange";
    assert wExp(input) <= maxOutput();
}

rule wExpIsMonotonicOnNegativeRange(int256 x) {
    require -maxInput() <= x && x < 0, "the positive range is proven in wExpIsMonotonicOnPositiveRangeWhenQStays/WhenQJumps";
    int256 x1 = assert_int256(x + 1);
    assert wExp(x) <= wExp(x1);
}

// q computed the same way as the inner branch of wExp on non-negative inputs.
function qOnPositiveRange(int256 x) returns mathint {
    mathint ln2 = 693147180559945309;
    mathint offset = 322611214989459870;
    return (x + offset) / ln2;
}

// Mirrors the Taylor series used inside wExp; only used as a hint for the rules below.
function expR(uint256 x) returns mathint {
    mathint ln2 = 693147180559945309;
    mathint offset = 322611214989459870;
    mathint q = (x + offset) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    return 10 ^ 18 + r + secondTerm + thirdTerm;
}

// Within a segment, x and x+1 differ only by r -> r+1, on which the Taylor series is increasing.
rule expRIsMonotonicWithinSegment(int256 x) {
    require 0 <= x && x < maxInput(), "wExp is only called on inputs in this range";
    int256 x1 = assert_int256(x + 1);
    require qOnPositiveRange(x) == qOnPositiveRange(x1), "x and x+1 are in the same segment";
    assert expR(assert_uint256(x)) <= expR(assert_uint256(x1));
}

// q changes by 0 or 1 between consecutive inputs; together with the two cases below this proves
// wExp monotonicity on the positive range. Splitting on q lets the solver pin the polynomial inputs
// (r) to constants at a jump, avoiding the tight symbolic nonlinear bound it cannot otherwise discharge.
rule qIncreasesByZeroOrOne(int256 x) {
    require 0 <= x && x < maxInput(), "wExp is only called on inputs in this range";
    int256 x1 = assert_int256(x + 1);
    mathint delta = qOnPositiveRange(x1) - qOnPositiveRange(x);
    assert delta == 0 || delta == 1;
}

// When q is unchanged the shift is identical on both sides, so wExp tracks the increasing expR series.
rule wExpIsMonotonicOnPositiveRangeWhenQStays(int256 x) {
    require 0 <= x && x < maxInput(), "the negative range is proven in wExpIsMonotonicOnNegativeRange";
    int256 x1 = assert_int256(x + 1);
    require qOnPositiveRange(x) == qOnPositiveRange(x1), "case: q stays the same";
    require expR(assert_uint256(x)) <= expR(assert_uint256(x1)), "by expRIsMonotonicWithinSegment";
    assert wExp(x) <= wExp(x1);
}

// When q increases by 1 the extra shift doubles the result, which covers the drop in expR.
rule wExpIsMonotonicOnPositiveRangeWhenQJumps(int256 x) {
    require 0 <= x && x < maxInput(), "the negative range is proven in wExpIsMonotonicOnNegativeRange";
    int256 x1 = assert_int256(x + 1);
    require qOnPositiveRange(x1) == qOnPositiveRange(x) + 1, "case: q increases by exactly 1";
    assert wExp(x) <= wExp(x1);
}

/// tickToPrice properties ///

// Useful for PriceToTick.spec
definition cvlMaxTick() returns uint256 = 6744;

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
