// SPDX-License-Identifier: GPL-2.0-or-later

import "TickToPrice.spec";

methods {
    function priceToTick(uint256 price, uint256 spacing) external returns (uint256) envfree;

    // Replaced by a ghost to model the deterministic behavior of tickToPrice, and to add the proven properties.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);
}

ghost ghostTickToPrice(uint256) returns uint256 {
    // matches rule tickToPriceIsOneAtMaxTick in TickToPrice.spec
    axiom ghostTickToPrice(cvlMaxTick()) == 10 ^ 18;

    // Proven by exhaustive testing on the relevant range in testTickMonotonicity.
    axiom forall uint256 t1. forall uint256 t2. t1 < t2 => ghostTickToPrice(t1) <= ghostTickToPrice(t2);
}

function summaryTickToPrice(uint256 tick) returns (uint256) {
    bool shouldRevert;
    if (shouldRevert || tick > maxTick()) {
        revert();
    }
    return ghostTickToPrice(tick);
}

rule priceToTickIsMonotonic(uint256 price1, uint256 price2, uint256 spacing) {
    assert price1 < price2 => priceToTick(price1, spacing) <= priceToTick(price2, spacing);
}

// For prices smaller than 1, priceToTick returns a tick with a price greater than or equal to the input price.
rule priceToTickReturnsATickWithGreaterThanOrEqualPrice(uint256 price, uint256 spacing) {
    require price <= 10 ^ 18, "assume that the price is smaller than 1";
    uint256 tick = priceToTick(price, spacing);
    assert tickToPrice(tick) >= price;
}

rule priceToTickReturnsLowestMultipleOfSpacing(uint256 price, uint256 spacing) {
    uint256 tick = priceToTick(price, spacing);
    require tick > 0, "for tick 0 it is trivially the lowest tick";
    assert tickToPrice(assert_uint256(tick - spacing)) < price;
}

// If tick is a multiple of spacing, then the recovered tick from priceToTick verifies:
// recoveredTick <= tick, and
// tickToPrice(recoveredTick) == tickToPrice(tick)
rule priceToTickRoundTrip(uint256 tick, uint256 spacing) {
    require spacing > 0, "a created market has a positive spacing, by definition";
    require tick % spacing == 0, "tick is not a multiple of spacing";
    uint256 price = tickToPrice(tick);
    uint256 recoveredTick = priceToTick(price, spacing);
    assert recoveredTick <= tick;
    assert tickToPrice(recoveredTick) == price;
}
