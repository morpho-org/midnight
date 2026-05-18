// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that successful calls do not overflow in mulDivDown or mulDivUp.
//
// mulDivDown(x, y, d) computes (x * y) / d with Solidity 0.8 checked arithmetic.
// mulDivUp(x, y, d) computes (x * y + (d - 1)) / d with Solidity 0.8 checked arithmetic.
// The multiplication x * y must not exceed type(uint256).max, or the transaction reverts.
//
// The toId summary follows the approach from CreatedMarkets.spec and encodes
// market field bounds (lltv, maxLif) proven in other specs, plus the realistic
// timestamp range assumption used by this overflow-focused proof.
//
// Oracle integration assumption: every (collateralAmount * oraclePrice) fits in uint256.
// Storage collateral is uint128, so boundedPrice enforces the product bound against max_uint128.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Oracle integration assumption: see header.
    function _.price() external => boundedPrice(calledContract) expect(uint256);

    // Deterministic toId: links call-site markets to validated state from touchMarket.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Sound return bound: tickToPrice <= WAD for non-reverting calls.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
    // Wildcard contract: maxLif is a free function and is called from both Midnight and Utils.
    function _.maxLif(uint256 lltv, uint256 cursor) internal => maxLifSummary(lltv) expect(uint256);

    // Summarize mulDivDown and mulDivUp to track overflow.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// GHOSTS ///

persistent ghost bool mulOverflow;

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition validMaxLif(uint256 x) returns bool = x >= WAD() && x <= 2 * WAD();

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// Proven in CreatedMarkets.spec (createdMarketsHaveLltvLessThanOrEqualToOne)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity is bounded to uint64 as a realistic timestamp assumption for overflow analysis.
function summaryToId(Midnight.Market market) returns (bytes32) {
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "lltv <= WAD: proven in CreatedMarkets.spec";
    require forall uint256 i. i < market.collateralParams.length => validMaxLif(market.collateralParams[i].maxLif), "WAD <= maxLif <= 2 * WAD: proven in ExactMath.spec";
    require market.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
    return Utils.hashMarket(market);
}

// Bound every storage collateral (uint128) * oracle price product.
function boundedPrice(address oracle) returns uint256 {
    uint256 price;
    require to_mathint(price) * max_uint128 + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "collateral (uint128) * price fits in uint256 with mulDivUp rounding headroom";
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price <= WAD(), "Proven in TickToPrice.spec";
    return price;
}

// Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
function maxLifSummary(uint256 lltv) returns uint256 {
    uint256 result;
    require validMaxLif(result), "WAD <= maxLif <= 2 * WAD: proven in ExactMath.spec";
    return result;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product, "proven in MulDiv.spec (mulDivDownRoundsDown)";
    require d == 0 || y > d || result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d == 0 || x > d || result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256 || (d > 0 && product + d - 1 > max_uint256)) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product + d - 1, "proven in MulDiv.spec (mulDivUpUpperBound)";
    require d == 0 || y > d || result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d == 0 || x > d || result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

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
