// SPDX-License-Identifier: GPL-2.0-or-later

// Proves that successful calls do not overflow in mulDivDown or mulDivUp.
//
// mulDivDown(x, y, d) computes (x * y) / d with Solidity 0.8 checked arithmetic.
// mulDivUp(x, y, d) computes (x * y + (d - 1)) / d with Solidity 0.8 checked arithmetic.
// The multiplication x * y must not exceed type(uint256).max, or the transaction reverts.
//
// maxLif(uint256, uint256) is excluded: it is a pure function callable with arbitrary inputs.
// Internal calls use WAD-scale values where its intermediate multiplications (WAD * WAD = 1e36 and cursor * (WAD - lltv) <= WAD^2 = 1e36) cannot overflow uint256.
//
// The toId summary follows the approach from CreatedObligations.spec and encodes
// obligation field bounds (lltv, maxLif) proven in other specs, plus the realistic
// timestamp range assumption used by this overflow-focused proof.
//
// Oracle integration assumption: every (collateralAmount * oraclePrice) fits in uint256.
// Storage collateral is uint128, so boundedPrice enforces the product bound against max_uint128.
// Liquidate also applies it to seizedAssets/repaidUnits via liquidateAmount. This is an
// integration assumption: arbitrary oracle contracts can still return unconstrained uint256 values.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Oracle integration assumption: see header.
    function _.price() external => boundedPrice(calledContract) expect(uint256);

    // Deterministic toId: links call-site obligations to validated state from touchObligation.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    // Hash/proof helpers are irrelevant to the multiplication-overflow property.
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // Sound return bound: tickToPrice <= WAD for non-reverting calls.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => boundedTickPrice();

    // Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
    function Midnight.maxLif(uint256 lltv, uint256 cursor) internal returns (uint256) => maxLifSummary(lltv);

    // Summarize mulDivDown and mulDivUp to track overflow.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivDownSummary(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => mulDivUpSummary(x, y, d);
}

/// GHOSTS ///

persistent ghost bool mulOverflow;

// Set by noMultiplicationOverflowLiquidate to max(seizedAssets, repaidUnits).
// 0 elsewhere makes the extra product bound vacuous.
persistent ghost uint256 liquidateAmount;

// Oracle for collateralIndex in noMultiplicationOverflowLiquidate.
// Gates liquidateAmount * price to the liquidated collateral's oracle.
persistent ghost address liquidatedOracle;

/// SUMMARIES ///

definition WAD() returns uint256 = 1000000000000000000;

definition ORACLE_PRICE_SCALE() returns uint256 = 1000000000000000000000000000000000000;

// Proven in CreatedObligations.spec (createdObligationsHaveLltvLessThanOrEqualToOne)
// and ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
// Maturity is bounded to uint64 as a realistic timestamp assumption for overflow analysis.
function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD(), "lltv <= WAD: proven in CreatedObligations.spec";
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].maxLif >= WAD() && obligation.collateralParams[i].maxLif <= 2 * WAD(), "WAD <= maxLif <= 2 * WAD: proven in ExactMath.spec";
    require obligation.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
    return Utils.hashObligation(obligation);
}

// Bound every storage collateral (uint128) * oracle price product.
// For liquidate's uint256 inputs, apply the same bound only to the liquidated collateral's oracle.
function boundedPrice(address oracle) returns uint256 {
    uint256 price;
    require to_mathint(price) * max_uint128 + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "collateral (uint128) * price fits in uint256 with mulDivUp rounding headroom";
    require oracle != liquidatedOracle || to_mathint(liquidateAmount) * price + ORACLE_PRICE_SCALE() - 1 <= max_uint256, "liquidate's seizedAssets/repaidUnits (uint256) * liquidatedCollatPrice fits in uint256 with mulDivUp rounding headroom";
    return price;
}

// Sound: tickToPrice = 1e36 / (1e18 + wExp(...)) and wExp(x) >= 0, so result <= WAD.
function boundedTickPrice() returns uint256 {
    uint256 price;
    require price <= WAD();
    return price;
}

// Proven in ExactMath.spec (maxLifIsAtLeastWad, maxLifIsAtMostTwoWad).
function maxLifSummary(uint256 lltv) returns uint256 {
    uint256 result;
    require result >= WAD();
    require result <= 2 * WAD();
    return result;
}

function mulDivDownSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product;
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;

    return result;
}

function mulDivUpSummary(uint256 x, uint256 y, uint256 d) returns uint256 {
    mathint product = to_mathint(x) * y;
    if (product > max_uint256 || (d > 0 && product + d - 1 > max_uint256)) {
        mulOverflow = true;
    }

    uint256 result;
    require d > 0 => result * d <= product + d - 1;
    require d == 0 || y > d || result <= x;
    require d == 0 || x > d || result <= y;

    return result;
}

// See summaryToId for full justification of each bound.
function requireObligationBounds(Midnight.Obligation obligation) {
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD(), "lltv <= WAD: proven in CreatedObligations.spec";
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].maxLif >= WAD() && obligation.collateralParams[i].maxLif <= 2 * WAD(), "WAD <= maxLif <= 2 * WAD: proven in ExactMath.spec";
    require obligation.maturity <= max_uint64, "maturity fits in uint64: realistic timestamp assumption";
}

// Reset oracle-related ghosts so non-liquidate rules don't carry over the extra product bound.
function resetOraclePriceAssumption() {
    liquidateAmount = 0;
    liquidatedOracle = 0;
}

/// RULES ///

// Normal calls intentionally scope this proof to non-reverting executions.
// Exclude maxLif (see header), liquidate (dedicated input bound), and view functions with arbitrary ids.
rule noMultiplicationOverflow(method f, env e, calldataarg args)
filtered {
    f -> f.selector != sig:maxLif(uint256, uint256).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector
        && f.selector != sig:isHealthy(Midnight.Obligation, bytes32, address).selector
        && f.selector != sig:updatePositionView(Midnight.Obligation, bytes32, address).selector
} {
    resetOraclePriceAssumption();
    require !mulOverflow, "prestate: no overflow before call";
    f(e, args);
    assert !mulOverflow;
}

// View functions take id as a separate parameter (not derived from the obligation),
// so summaryToId bounds don't apply. Explicit obligation bounds are needed.

rule noMultiplicationOverflowIsHealthy(env e, Midnight.Obligation obligation, bytes32 id, address borrower) {
    resetOraclePriceAssumption();
    require !mulOverflow, "prestate: no overflow before call";
    requireObligationBounds(obligation);
    isHealthy(e, obligation, id, borrower);
    assert !mulOverflow;
}

rule noMultiplicationOverflowUpdatePositionView(env e, Midnight.Obligation obligation, bytes32 id, address user) {
    resetOraclePriceAssumption();
    require !mulOverflow, "prestate: no overflow before call";
    requireObligationBounds(obligation);
    updatePositionView(e, obligation, id, user);
    assert !mulOverflow;
}

// liquidate's seizedAssets/repaidUnits are uint256 function inputs (not the uint128 storage
// already covered by boundedPrice). Set liquidateAmount to their max and liquidatedOracle to
// the oracle of collateralIndex so boundedPrice extends the same (amount * price) bound only
// to that oracle's price (the one actually multiplied with the function inputs).
rule noMultiplicationOverflowLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    resetOraclePriceAssumption();
    liquidateAmount = seizedAssets > repaidUnits ? seizedAssets : repaidUnits;
    liquidatedOracle = obligation.collateralParams[collateralIndex].oracle;
    require !mulOverflow, "prestate: assume no overflow before liquidate";
    requireObligationBounds(obligation);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);
    assert !mulOverflow;
}
