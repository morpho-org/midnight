// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Proves that the only overflows in mulDivDown and mulDivUp that can cause a revert are
// the ones that compute the value of a collateral against the oracle price.
// These can only overflow if the collateral is priced at more than max_uint128 debt units,
// which is documented in Midnight.sol.

// Strictly speaking, other mulDivDown/mulDivUp may revert due to overflow, e.g.,
// for withdraw a mulDiv can revert for very large values of units > 2^128.
// However, this would result in a different revert, if the mulDiv is never called.
// This spec checks for overflows at the end, showing that if there is no other reason the
// call would have reverted the mulDiv didn't overflow.
// Thus, the mulDiv did not singlehandedly cause the revert.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic summary for oracle price
    function _.price() external => getOraclePrice(calledContract) expect(uint256);

    // Deterministic toId: links call-site markets to validated state from touchMarket.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Sound return bound: tickToPrice <= WAD for non-reverting calls.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Summarize mulDivDown and mulDivUp to track overflow.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);

    // Summarize maxLif by a deterministic ghost so its value can be assumed under a quantifier.
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);
}

/// HELPERS ///

persistent ghost bool mulOverflow;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

ghost oraclePriceGhost(address) returns uint256;

ghost uint256 lastOraclePrice;

ghost uint256 lastCollateralAmount;

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// Proven in CreatedMarkets.spec (createdMarketsHaveEnabledLltv)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity is bounded to uint64 as a realistic timestamp assumption for overflow analysis.
function summaryToId(Midnight.Market market) returns (bytes32) {
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "proven in CreatedMarkets.spec";
    require forall uint256 i. i < market.collateralParams.length => maxLifGhost(market.collateralParams[i].lltv, market.collateralParams[i].liquidationCursor) >= WAD() && maxLifGhost(market.collateralParams[i].lltv, market.collateralParams[i].liquidationCursor) <= 2 * WAD(), "see maxLifIsAtLeastWad and createdMarketsHaveMaxLifAtMostTwoWad";
    require market.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
    return Utils.hashMarket(market);
}

// hook to remember the last queried collateral amount.
hook Sload uint128 value position[KEY bytes32 id][KEY address user].collateral[INDEX uint256 collateralIndex] {
    lastCollateralAmount = value;
}

// internal function to remember the last queried oracle price.
function getOraclePrice(address oracle) returns uint256 {
    uint256 price = oraclePriceGhost(oracle);
    lastOraclePrice = price;
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price <= WAD(), "Proven in TickToPrice.spec";
    return price;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    mathint product = x * y;
    if (product > max_uint256) {
        // overflow in mulDivDown
        if (x == lastCollateralAmount && y == lastOraclePrice && d == ORACLE_PRICE_SCALE()) {
            // Explicitly allow to revert when some user's collateral is priced at too many debt units
            // This assert double-checks that a revert only happens in this case.
            // Gap: here we assume that collateral and oracle price match. A bug where the wrong collateral index is used for the oracle is not detected by this spec.
            assert lastCollateralAmount * lastOraclePrice / ORACLE_PRICE_SCALE() > max_uint128, "collateral worth more than max_uint128 debt units";
            revert();
        } else {
            // other overflows are checked at the end that they didn't cause a revert.
            mulOverflow = true;
            return result;
        }
    }

    // These requires are proved for the no-overflow case.
    require d > 0 => result * d <= product, "proven in MulDiv.spec (mulDivDownRoundsDown)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 result;
    mathint product = x * y;
    if (product > max_uint256 || (d > 0 && product + d - 1 > max_uint256)) {
        // overflow in mulDivUp
        if (x == lastCollateralAmount && y == lastOraclePrice && d == ORACLE_PRICE_SCALE()) {
            // Explicitly allow to revert when some user's collateral is priced at too many debt units
            // This assert double-checks that a revert only happens in this case.
            // Gap: here we assume that collateral and oracle price match. A bug where the wrong collateral index is used for the oracle is not detected by this spec.
            assert lastCollateralAmount * lastOraclePrice / ORACLE_PRICE_SCALE() > max_uint128, "collateral worth more than max_uint128 debt units";
            revert();
        } else {
            // other overflows are checked at the end that they didn't cause a revert.
            mulOverflow = true;
            return result;
        }
    }

    // These requires are proved for the no-overflow case.
    require d > 0 => result * d <= product + d - 1, "proven in MulDiv.spec (mulDivUpUpperBound)";
    require d > 0 => y <= d => result <= x, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";
    require d > 0 => x <= d => result <= y, "proven in MulDiv.spec (mulDivArgumentLesserThanDenominator)";

    return result;
}

/// RULES ///

// Normal calls intentionally scope this proof to non-reverting executions.
// The updatePositionView and isHealthy have dedicated rules to ensure market and id match.
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
