// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function lnOnePlusDelta() external returns (int256) envfree;
    function maxTick() external returns (uint256) envfree;
    function wExp(int256 x) external returns (uint256) envfree;
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
}

function expR(uint256 x) returns mathint {
    mathint ln2 = 693147180559945309;
    mathint offset = 32261121498945987;
    mathint q = (x + offset) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    return 10 ^ 18 + r + secondTerm + thirdTerm;
}

// Check the casting assertions in the wExp function.
rule wExpCasting(uint256 x) {
    require x >= 0, "wExp calls wExp(-x) when x < 0";

    mathint ln2 = 693147180559945309;
    mathint offset = 32261121498945987;
    mathint q = (x + offset) / ln2;
    mathint r = x - q * ln2;
    mathint secondTerm = r * r / (2 * 10 ^ 18);
    mathint thirdTerm = secondTerm * r / (3 * 10 ^ 18);
    mathint expR = 10 ^ 18 + r + secondTerm + thirdTerm;

    assert q >= 0;
    assert r < ln2 && r > -ln2;
    assert expR >= 0;
}

rule expRCantGoMoreThanTimesTwo(uint256 x, uint256 y) {
    assert expR(x) <= 2 * expR(y);
}

definition maxInput() returns int256 = assert_int256(lnOnePlusDelta() * (maxTick() / 2));

definition maxOutput() returns uint256 = 2010201770916298901946368;

rule maxOutputIsWExpOfMaxInput() {
    assert maxOutput() == wExp(maxInput());
}

rule wExpIsMonotonicOnPositiveRange(int256 x1) {
    require 0 <= x1 && x1 < maxInput();
    require expR(require_uint256(x1)) <= 2 * expR(require_uint256(x1 + 1)),
        "by expRCantGoMoreThanTimesTwo";
    assert wExp(x1) <= wExp(assert_int256(x1 + 1));
}

rule wExpIsMonotonicOnNegativeRange(int256 x1) {
    assert -maxInput() <= x1 && x1 < 0 => wExp(assert_int256(x1 - 1)) <= wExp(x1);
}

rule wExpOutputBound(int256 input) {
    require -maxInput() <= input && input <= maxInput(), "sound because wExp is only called on inputs in this range";
    require wExp(input) <= wExp(maxInput()), "see rules wExpIsMonotonicOnPositiveRange and wExpIsMonotonicOnNegativeRange";
    assert wExp(input) <= maxOutput();
}
