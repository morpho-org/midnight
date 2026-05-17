// SPDX-License-Identifier: GPL-2.0-or-later

import "WExp.spec";

methods {
    // Internal calls to TickLib.wExp are replaced by the ghost. The axioms below match the
    // properties separately proven on the real function in WExp.spec.
    function TickLib.wExp(int256 x) internal returns (uint256) => summaryWExp(x);
}

persistent ghost ghostWExp(int256) returns uint256 {
    // matches rule wExpIsMonotonic in WExp.spec
    axiom forall int256 x1. forall int256 x2. x1 < x2 => ghostWExp(x1) <= ghostWExp(x2);

    // matches rule wExpOutputBound in WExp.spec
    // Needed to show that the computation 1e18 + wExp(...) does not overflow in tickToPrice.
    axiom forall int256 x. ghostWExp(x) <= maxOutput();
}

function summaryWExp(int256 x) returns (uint256) {
    bool shouldRevert;
    if (shouldRevert) {
        revert();
    }
    return ghostWExp(x);
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
