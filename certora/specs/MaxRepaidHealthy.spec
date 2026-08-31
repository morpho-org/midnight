// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";
import "MulDivAxioms.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function debt(bytes32 id, address user) external returns (uint128) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function maxRepaidFor(Midnight.Market, bytes32, uint256, address) external returns (uint256) envfree;

    // Assumption: price does not change during the rule (same value in maxRepaidFor, in liquidate and in the
    // post-state isHealthyNoBitmap). Deterministic per oracle address, as in Healthiness.spec.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // The three summaries below do not restrict the verified behaviours:
    // - tickToPrice: NONDET havocs the return value, which is an over-approximation (it allows every tick
    //   price, including the real one). Tick prices only feed the order-book accounting, never the health
    //   computation this rule reasons about, so losing that information costs nothing.
    // - toId: replaces the keccak derivation by a ghost that is only required to be deterministic and
    //   injective on the pinned market. Both hold for the real derivation up to hash collisions, which is
    //   the standing assumption everywhere ids are summarized (see Healthiness.spec).
    // - storeInCode: NONDET havocs the returned address. The function only mirrors the market into code for
    //   cheap retrieval; the position and market storage the rule reads is untouched, so over-approximating
    //   the address it returns cannot hide a counterexample.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Summarizing mulDivDown and mulDivUp by unconstrained deterministic ghosts adds no assumption about
    // mulDiv: the ghosts are arbitrary, and the summaries revert on a nondeterministic overflow flag, so
    // every real mulDiv behaviour is still allowed. All the arithmetic the rule actually needs is required
    // explicitly below, one ground instance per rule proved over the concrete mulDiv in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // maxLif is deterministic for each (lltv, liquidationCursor) pair.
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // Unresolved callbacks and token calls use AUTO/HAVOC_ECF, which models non-reentrant callees.
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition WAD_SQUARED() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || a * b >= 2 ^ 256) {
        revert();
    }
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || a * b + d - 1 >= 2 ^ 256) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
}

// Pin every field that contributes to the market id, making the toId summary deterministic and injective.

persistent ghost address globalMarketLoanToken;

persistent ghost uint256 globalMarketChainId;

// Exactly two collaterals is not a restriction on the result. Liquidating touches a single collateral, so the
// whole contribution of every other collateral to maxDebt enters the reasoning as one arbitrary non-negative
// value, and one extra collateral with an arbitrary amount, price and LLTV already realizes every such value.
// The second collateral therefore plays the role of the arbitrary otherCollatContribution of the Rocq proof,
// and a market with more collaterals is covered by the same argument.
persistent ghost uint256 globalMarketCollateralLength {
    axiom globalMarketCollateralLength == 2;
}

persistent ghost mapping(uint256 => address) globalMarketCollateralOracle;

persistent ghost mapping(uint256 => address) globalMarketCollateralToken;

persistent ghost mapping(uint256 => uint256) globalMarketCollateralLLTV;

persistent ghost mapping(uint256 => uint256) globalMarketCollateralLiquidationCursor;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost uint256 globalMarketMaturity;

persistent ghost uint256 globalMarketRcfThreshold;

persistent ghost address globalMarketEnterGate;

persistent ghost address globalMarketLiquidatorGate;

persistent ghost bytes32 globalId;

definition collateralMatches(Midnight.Market market, uint256 index) returns bool = (index < globalMarketCollateralLength => market.collateralParams[index].oracle == globalMarketCollateralOracle[index] && market.collateralParams[index].token == globalMarketCollateralToken[index] && market.collateralParams[index].lltv == globalMarketCollateralLLTV[index] && market.collateralParams[index].liquidationCursor == globalMarketCollateralLiquidationCursor[index]);

function equalsGlobalMarket(Midnight.Market market) returns (bool) {
    return market.chainId == globalMarketChainId && market.midnight == currentContract && market.loanToken == globalMarketLoanToken && market.collateralParams.length == globalMarketCollateralLength && collateralMatches(market, 0) && collateralMatches(market, 1) && market.maturity == globalMarketMaturity && market.rcfThreshold == globalMarketRcfThreshold && market.enterGate == globalMarketEnterGate && market.liquidatorGate == globalMarketLiquidatorGate;
}

function getGlobalMarket() returns (Midnight.Market) {
    Midnight.Market market;
    require equalsGlobalMarket(market), "get global market";
    return market;
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    bytes32 id;
    if (equalsGlobalMarket(market)) {
        require id == globalId, "toId() is deterministic";
    } else {
        require id != globalId, "toId() is injective";
    }
    return id;
}

/// RULE ///

// In a two-collateral market, liquidating at the amount computed by maxRepaidFor leaves the position healthy.
// The call uses normal mode and covers the strictly unhealthy and health-boundary cases. See the
// globalMarketCollateralLength axiom for why two collaterals is general enough.
rule liquidateAtCapRestoresHealth(env e, uint256 collateralIndex, address borrower, address receiver, address callback, bytes data) {
    Midnight.Market globalMarket = getGlobalMarket();

    uint256 collatBefore = collateral(globalId, borrower, collateralIndex);
    uint256 debtBefore = debt(globalId, borrower);

    // This rule checks that using `repaidUnits == maxRepaid` is enough to put the account healthy. This means that the RCF doesn't prevent to put the position back to health.
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, borrower);

    // maxRepaidFor's non-reverting collateral lookup establishes collateralIndex < 2.
    uint256 otherIndex = assert_uint256(1 - collateralIndex);
    uint256 otherCollatBefore = collateral(globalId, borrower, otherIndex);
    uint256 otherLltv = globalMarketCollateralLLTV[otherIndex];
    uint256 otherPrice = summaryPrice(globalMarket.collateralParams[otherIndex].oracle);

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate(e, globalMarket, collateralIndex, 0, repaidUnits, borrower, false, receiver, callback, data);

    uint256 collatAfter = assert_uint256(collatBefore - seizedOut);
    bool isHealthyAfter = isHealthyNoBitmap(globalMarket, globalId, borrower);

    /// MAX-DEBT DROP BOUND ///
    // Establish curContrib - newContrib <= maxDebtDropBound. When it seizes, liquidate computes
    // seizedOut = floor(floor(repaidUnits * lif / WAD) * ORACLE_PRICE_SCALE / price), matching the ghost terms
    // below. Each require is one ground instance of a rule proved in MulDiv.spec.

    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);
    mathint maxSeizedValue = ghostMulDivDown(repaidUnits, lif, WAD());
    uint256 price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // By that same computation, seizedOut == ghostMulDivDown(maxSeizedValue, ORACLE_PRICE_SCALE(), price).
    mathint curCollatValue = ghostMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    mathint newCollatValue = ghostMulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());

    mathint curContrib = ghostMulDivDown(curCollatValue, lltv, WAD());
    mathint newContrib = ghostMulDivDown(newCollatValue, lltv, WAD());

    mathint lifTimesLltv = lif * lltv;
    mathint maxDebtDropBound = ghostMulDivUp(repaidUnits, lifTimesLltv, WAD_SQUARED());

    require axiomMathMulDivInverseUpDown(maxSeizedValue, ORACLE_PRICE_SCALE(), price), "axiom L1";
    require axiomMathMulDivAddDownUp(collatAfter, seizedOut, price, ORACLE_PRICE_SCALE()), "axiom L2";
    require axiomMathMulDivDownMonotoneA(curCollatValue, newCollatValue + maxSeizedValue, lltv, WAD()), "axiom L3";
    require axiomMathMulDivAddDownUp(newCollatValue, maxSeizedValue, lltv, WAD()), "axiom L3";
    require axiomMathMulDivDownUpComposition(repaidUnits, lif, lltv, WAD()), "axiom L4";

    // L1-L2 bound the collateral-value decrease by maxSeizedValue. L3 transports that bound through the LLTV
    // contribution, and L4 bounds the composed rounding by maxDebtDropBound.

    /// FINAL HEALTH BOUND ///
    // repaidUnits is ceil(gap * WAD^2 / (WAD^2 - lif * lltv)). The two rounding facts below imply
    // maxDebtDropBound <= repaidUnits - gap. Therefore the new max debt falls by no more than the amount
    // repaid in excess of the old health gap.
    mathint otherCollatValue = ghostMulDivDown(otherCollatBefore, otherPrice, ORACLE_PRICE_SCALE());
    mathint otherContrib = ghostMulDivDown(otherCollatValue, otherLltv, WAD());
    mathint maxDebtBefore = curContrib + otherContrib;

    mathint gap = debtBefore - maxDebtBefore;
    mathint rcfDenominator = WAD_SQUARED() - lifTimesLltv;
    require axiomMathMulDivUpRoundsUp(gap, WAD_SQUARED(), rcfDenominator), "axiom";
    mathint repaidExcess = repaidUnits - gap;
    require axiomMathMulDivCeilLeOfMulGe(repaidUnits, lifTimesLltv, WAD_SQUARED(), repaidExcess), "axiom";

    assert isHealthyAfter;
}
