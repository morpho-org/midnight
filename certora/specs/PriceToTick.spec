// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function maxTick() external returns (uint256) envfree;
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
    function priceToTick(uint256 price, uint256 spacing) external returns (uint256) envfree;

    // Internal calls to TickLib.tickToPrice are replaced by the ghost. The axioms below match the
    // properties separately proven on the real function in TickLib.spec.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => summaryTickToPrice(tick);
}

ghost ghostTickToPrice(uint256) returns uint256 {
    // matches rule tickToPriceAtMostWad in TickLib.spec
    axiom forall uint256 t. ghostTickToPrice(t) <= 10 ^ 18;

    // matches rule tickToPriceIsMonotonic in TickLib.spec
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

rule priceToTickReturnsATickWithGreaterThanOrEqualPrice(uint256 price, uint256 spacing) {
    // require price <= tickToPrice(maxTick()), "price must be representable; tickToPrice rounds down at MAX_TICK";
    uint256 tick = priceToTick(price, spacing);
    assert tickToPrice(tick) >= price;
}

rule priceToTickReturnsLowestTickWithGreaterThanOrEqualPrice(uint256 price, uint256 spacing) {
    uint256 tick = priceToTick(price, spacing);
    require tick > 0, "for tick 0 it is trivially the lowest tick";
    assert tickToPrice(assert_uint256(tick - spacing)) < price;
}

// If the tick is a multiple of spacing, and writing price:=tickToPrice(tick), then:
// - priceToTick(price, spacing) <= tick
// - tickToPrice(priceToTick(price, spacing)) == price
rule priceToTickRoundTrip(uint256 tick, uint256 spacing) {
    require spacing > 0, "a created market has a positive spacing, by definition";
    require tick % spacing == 0, "tick is not a multiple of spacing";
    uint256 price = tickToPrice(tick);
    uint256 recoveredTick = priceToTick(price, spacing);
    assert recoveredTick <= tick;
    assert tickToPrice(recoveredTick) == price;
}
