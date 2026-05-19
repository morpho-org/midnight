// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that successful calls do not overflow in mulDivDown or mulDivUp, given the oracle price is bounded.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Oracle integration assumption: every (collateralAmount * oraclePrice) fits in uint256.
    // Storage collateral is uint128, so boundedPrice enforces the product bound against max_uint128.
    function _.price() external => boundedPrice(calledContract) expect(uint256);

    // Deterministic toId: links call-site markets to validated state from touchMarket.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Sound return bound: tickToPrice <= WAD for non-reverting calls.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Summarize mulDivDown and mulDivUp to track overflow.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// HELPERS ///

persistent ghost bool mulOverflow;

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// Proven in CreatedMarkets.spec (createdMarketsHaveLltvLessThanOrEqualToOne)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity is bounded to uint64 as a realistic timestamp assumption for overflow analysis.
function summaryToId(Midnight.Market market) returns (bytes32) {
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "proven in CreatedMarkets.spec";
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].maxLif >= WAD() && market.collateralParams[i].maxLif <= 2 * WAD(), "proven in ExactMath.spec";
    require market.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
    return Utils.hashMarket(market);
}

// Bound every storage collateral (uint128) * oracle price product.
function boundedPrice(address oracle) returns uint256 {
    uint256 price;
    require to_mathint(price) * max_uint128 + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "same as assuming that collateral * price <= uint256 with mulDivUp rounding headroom";
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price <= WAD(), "Proven in TickToPrice.spec";
    return price;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product, "proven in MulDiv.spec (mulDivDownRoundsDown)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256 || (d > 0 && product + d - 1 > max_uint256)) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product + d - 1, "proven in MulDiv.spec (mulDivUpUpperBound)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

    return result;
}

/// RULES ///

// Normal calls intentionally scope this proof to non-reverting executions.
// The updatePositionView and isHealthy have dedicated rules.
rule noMultiplicationOverflow(method f, env e, calldataarg args) filtered { f -> f.selector != sig:isHealthy(Midnight.Market, bytes32, address).selector && f.selector != sig:updatePositionView(Midnight.Market, bytes32, address).selector } {
    require !mulOverflow, "prestate: no overflow before call";
    f(e, args);
    assert !mulOverflow;
}

rule noMultiplicationOverflowIsHealthy(env e, Midnight.Market market, bytes32 id, address borrower) {
    require !mulOverflow, "prestate: no overflow before call";
    require id == summaryToId(market), "id corresponds to market";
    isHealthy(e, market, id, borrower);
    assert !mulOverflow;
}

rule noMultiplicationOverflowUpdatePositionView(env e, Midnight.Market market, bytes32 id, address user) {
    require !mulOverflow, "prestate: no overflow before call";
    require id == summaryToId(market), "id corresponds to market";
    updatePositionView(e, market, id, user);
    assert !mulOverflow;
}
