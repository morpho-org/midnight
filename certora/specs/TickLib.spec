methods {
    function tickToPrice(uint256 tick) external returns (uint256) envfree;
    function priceToTick(uint256 price, uint256 spacing) external returns (uint256) envfree;
}

//ghost mapping(uint256 => uint256) ghostTickToPrice {
//init_state axiom (forall uint256 tick. ghostTickToPrice[tick] == tickToPrice(tick));
//}

// Tick to price is at most 1e18.
// This notably ensures that offer prices are at most 1e18.
rule tickToPriceAtMostWad(uint256 tick) {
    assert tickToPrice(tick) <= 10 ^ 18;
}

rule tickToPriceIsMonotonic(uint256 tick1, uint256 tick2) {
    assert tick1 < tick2 => tickToPrice(tick1) <= tickToPrice(tick2);
}

rule tickToPriceIsZeroAtZero() {
    assert tickToPrice(0) == 0;
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

rule priceToTickIsMonotonic(uint256 price1, uint256 price2, uint256 spacing) {
    assert price1 < price2 => priceToTick(price1, spacing) <= priceToTick(price2, spacing);
}

rule priceToTickReturnsATickWithGreaterThanOrEqualPrice(uint256 price, uint256 spacing) {
    uint256 tick = priceToTick(price, spacing);
    assert tickToPrice(tick) >= price;
}

rule priceToTickReturnsLowestTickWithGreaterThanOrEqualPrice(uint256 price, uint256 spacing) {
    uint256 tick = priceToTick(price, spacing);
    require tick > 0, "for tick 0 it is trivially the lowest tick";
    assert tickToPrice(assert_uint256(tick - spacing)) < price;
}

// If the tick is a multiple of spacing, then priceToTick(tickToPrice(tick), spacing) == tick.
rule priceToTickRoundTrip(uint256 tick, uint256 spacing) {
    require tick % spacing == 0, "tick is not a multiple of spacing";
    uint256 price = tickToPrice(tick);

    // require forall uint256 i. forall uint256 j. i < j => tickToPrice(i) <= tickToPrice(j), "see tickToPriceIsMonotonic";
    assert priceToTick(price, spacing) == tick;
}
