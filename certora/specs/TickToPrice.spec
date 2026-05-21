// SPDX-License-Identifier: GPL-2.0-or-later

import "WExp.spec";

methods {
    function wExp(int256 x) internal returns (uint256) => summaryWExp(x);
}

persistent ghost summaryWExp(int256) returns uint256 {
    // The rule wExpIsMonotonicOnPositiveRange and wExpIsMonotonicOnNegativeRange in WExp.spec prove that wExp is non-decreasing.
    axiom forall int256 x. forall int256 y. x <= y => summaryWExp(x) <= summaryWExp(y);

    // matches rule maxOutputIsWExpOfMaxInput in WExp.spec
    axiom summaryWExp(maxInput()) == maxOutput();
}

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

// Tick to price is at most 1e18.
// This notably ensures that offer prices are at most 1e18.
rule tickToPriceAtMostWad(uint256 tick) {
    assert tickToPrice(tick) <= 10 ^ 18;
}

rule tickToPriceIsMonotonic(uint256 tick1, uint256 tick2) {
    assert tick1 < tick2 => tickToPrice(tick1) <= tickToPrice(tick2);
}
