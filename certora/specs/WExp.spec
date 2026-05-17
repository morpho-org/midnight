// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function lnOnePlusDelta() external returns (int256) envfree;
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

definition maxInput() returns int256 = assert_int256(lnOnePlusDelta() * (maxTick() / 2));

definition maxOutput() returns uint256 = 2010201770916298901946368;

rule wExpOutputBound(int256 input) {
    require -maxInput() <= input && input <= maxInput(), "sound because wExp is only called on inputs in this range";
    assert wExp(input) <= maxOutput();
}

rule wExpIsMonotonic(int256 x1, int256 x2) {
    require -maxInput() <= x1 && x1 <= maxInput(), "sound because wExp is only called on inputs in this range";
    require -maxInput() <= x2 && x2 <= maxInput(), "sound because wExp is only called on inputs in this range";
    assert x1 < x2 => wExp(x1) <= wExp(x2);
}
