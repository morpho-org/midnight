// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association

import "TickToPrice.spec";

methods {
    function TickLib.wExp(int256 x) internal returns (uint256) => summaryWExp(x);
}

persistent ghost summaryWExp(int256) returns uint256 {
    // See the rules in the wExp section of TickToPrice.spec, which together prove that wExp is non-decreasing on [-maxInput(), maxInput()].
    axiom forall int256 x. forall int256 y. -cvlMaxInput() <= x && x <= y && y <= cvlMaxInput() => summaryWExp(x) <= summaryWExp(y);
}

rule tickToPriceIsMonotonic(uint256 tick1, uint256 tick2) {
    require summaryWExp(maxInput()) == maxOutput(), "see rule maxOutputIsWExpOfMaxInput in WExp.spec";
    assert tick1 < tick2 => tickToPrice(tick1) <= tickToPrice(tick2);
}
