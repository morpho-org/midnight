// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function debt(bytes32 id, address user) external returns (uint128) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function maxRepaidFor(Midnight.Market, bytes32, uint256, address) external returns (uint256) envfree;
    function badDebtFor(Midnight.Market, bytes32, address) external returns (uint256) envfree;

    // Assumption: price does not change during the rule (same value in maxRepaidFor, in liquidate and in the
    // post-state isHealthyNoBitmap). Deterministic per oracle address, as in Healthiness.spec.
    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Summarize mulDivDown and mulDivUp deterministically; the tight rounding facts about them are proved
    // over concrete mulDiv in MulDiv.spec and injected below only at the specific instances the rule needs.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // maxLif is recomputed on the fly from (lltv, liquidationCursor); its lltv * maxLif <= WAD * WAD bound is
    // assumed below (see lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec).
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // Assume no reentrancy: callbacks and tokens do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own body on
    // the state, not the effect of the full transaction including callbacks.
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

/* Primitive tight rounding facts, each proven over concrete mulDiv in MulDiv.spec and used below ONLY at
   specific ground instances (never as background foralls, to keep the query linear). */

/* Proved in mulDivUpRoundsUp: a*b <= ceil(a*b/d)*d. */
definition axiomUpRoundsUp(uint256 a, uint256 b, uint256 d) returns bool = d > 0 => a * b <= ghostMulDivUp(a, b, d) * d;

/* Proved in mulDivCeilLeOfMulGe: a*b <= bound*d => ceil(a*b/d) <= bound. */
definition axiomCeilLeOfMulGe(uint256 a, uint256 b, uint256 d, uint256 bound) returns bool = d > 0 && a * b <= bound * d => ghostMulDivUp(a, b, d) <= bound;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

// Global market machinery (mirrors Healthiness.spec): pins the market so that IdLib.toId is deterministic and
// the collateral params are known. globalMarketCollateralLength is fixed to 1 in the rule (single collateral).

persistent ghost address globalMarketLoanToken;

persistent ghost uint256 globalMarketChainId;

persistent ghost uint256 globalMarketCollateralLength {
    axiom globalMarketCollateralLength <= 2;
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

// Single-collateral maxDebt contribution: floor(floor(collat * price / OPS) * lltv / WAD).
function maxDebtContribution(uint256 collat, uint256 price, uint256 lltv) returns uint256 {
    return ghostMulDivDown(ghostMulDivDown(collat, price, ORACLE_PRICE_SCALE()), lltv, WAD());
}

/// RULE ///

// Liquidating an unhealthy position at the RCF cap restores its health, in the single-collateral,
// RCF-active (!postMaturityMode && lltv < WAD), no-bad-debt regime, in the maxRepaid < debt case
// (newDebt = debt - maxRepaid > 0).
// The maxDebt-drop bound is DERIVED INLINE (see the "INLINE DROP-BOUND DERIVATION" block below).
rule liquidateAtCapRestoresHealth(env e, uint256 collateralIndex, address borrower, address receiver, address callback, bytes data) {
    // Post-state health is read bitmap-free; combined with single-collateral this avoids bitmap iteration.
    Midnight.Market globalMarket = getGlobalMarket();

    // Single collateral, so there is no contribution from other collateral.
    require globalMarketCollateralLength == 1, "single-collateral market";

    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);

    require lltv < WAD(), "RCF is active only for lltv < WAD";
    require lltv * lif <= 999 * 10 ^ 15 * WAD(), "maxLif * lltv <= 0.999 * WAD * WAD, (see Midnight.sol:698, createdMarketsRespectMaxLifBound in CreatedMarkets.spec, it makes the L699 denominator strictly positive)";

    address oracle = globalMarket.collateralParams[collateralIndex].oracle;
    uint256 price = summaryPrice(oracle);

    require price > 0, "positive price; otherwise mulDiv by price reverts and the case is vacuous";

    // On a non-reverting liquidation, the sole market collateral is activated and no out-of-range bitmap bit
    // can be set. The call also enforces that the borrower is not liquidation-locked.
    require currentContract.marketState[globalId].tickSpacing != 0, "market is already created, so touchMarket is a no-op that returns globalId";
    require badDebtFor(globalMarket, globalId, borrower) == 0, "no bad debt is realized, so liquidate's debt at L699 equals maxRepaidFor's pre-liquidation debt";
    require !isHealthyNoBitmap(globalMarket, globalId, borrower), "unhealthy pre-state: maxDebt < debt due to the strict RCF trigger at Midnight.sol:661";

    uint256 collatBefore = collateral(globalId, borrower, collateralIndex);
    uint256 debtBefore = debt(globalId, borrower);

    // Pin repaid to the RCF cap. maxRepaidFor reproduces Midnight.sol:699 exactly, so repaidUnits equals the
    // maxRepaid recomputed inside liquidate and the RCF require (Midnight.sol:700-705) passes on its first
    // disjunct (repaidUnits <= maxRepaid), independently of the dust waiver.
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, borrower);

    require repaidUnits < debtBefore, "maxRepaid < debt case: repaid = maxRepaid and newDebt > 0 (the maxRepaid >= debt case gives newDebt = 0, which is trivially healthy)";

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate(e, globalMarket, collateralIndex, 0, repaidUnits, borrower, false, receiver, callback, data);

    uint256 collatAfter = assert_uint256(collatBefore - seizedOut);

    // gap = debt - maxDebt > 0 (the position is unhealthy). Both are the single-collateral quantities that
    // liquidate uses internally: maxDebt at L699 and debt (unchanged, since no bad debt) equal these.
    uint256 gap = assert_uint256(debtBefore - maxDebtContribution(collatBefore, price, lltv));

    ///// INLINE DROP-BOUND DERIVATION /////
    // Establishes: curContrib - newContrib <= maxDebtDropBound. Ghost-form quantities mirror the
    // single-collateral definitions; liquidate computes seizedOut = floor(floor(repaid*lif/WAD)*OPS/price) at
    // Midnight.sol:692, so seizedOut IS the ghost term ghostMulDivDown(maxSeizedValue, OPS, price) below. Each
    // fact is a primitive rounding bound or a derived mulDiv identity proven over concrete mulDiv in
    // MulDiv.spec (rule name cited); the composition uses arithmetic glue.

    uint256 W = WAD();
    uint256 S = ORACLE_PRICE_SCALE();

    uint256 maxSeizedValue = ghostMulDivDown(repaidUnits, lif, W);

    // liquidate's L692 seizedAssets: seizedOut == ghostMulDivDown(maxSeizedValue, S, price).
    uint256 curCollatValue = ghostMulDivDown(collatBefore, price, S);
    uint256 newCollatValue = ghostMulDivDown(collatAfter, price, S);
    require newCollatValue <= curCollatValue, "mulDivMonotoneA with collatAfter <= collatBefore, so the collateral-value drop is non-negative (MulDiv.spec)";
    uint256 collatValueDrop = assert_uint256(curCollatValue - newCollatValue);

    uint256 curContrib = ghostMulDivDown(curCollatValue, lltv, W);
    uint256 newContrib = ghostMulDivDown(newCollatValue, lltv, W);

    uint256 lifTimesLltv = assert_uint256(lif * lltv);
    uint256 maxDebtDropBound = ghostMulDivUp(repaidUnits, lifTimesLltv, S);

    require ghostMulDivUp(seizedOut, price, S) <= maxSeizedValue, "L1: mulDivInverseUpDown with a=maxSeizedValue, b=S, d=price (MulDiv.spec)";
    require curCollatValue <= newCollatValue + ghostMulDivUp(seizedOut, price, S), "L2: mulDivAddDownUp with a1=collatAfter, a2=seizedOut, b=price, d=S (MulDiv.spec)";
    require curContrib <= newContrib + ghostMulDivUp(collatValueDrop, lltv, W), "L3: mulDivAddDownUp with a1=newCollatValue, a2=collatValueDrop, b=lltv, d=W (MulDiv.spec)";
    require collatValueDrop <= maxSeizedValue => ghostMulDivUp(collatValueDrop, lltv, W) <= ghostMulDivUp(maxSeizedValue, lltv, W), "L4: mulDivMonotoneA with a1=collatValueDrop, a2=maxSeizedValue, b=lltv, d=W (MulDiv.spec)";
    require maxSeizedValue * W <= repaidUnits * lif, "L5.a: mulDivDownRoundsDown with a=repaidUnits, b=lif, d=W (MulDiv.spec)";
    require maxDebtDropBound * S >= repaidUnits * lifTimesLltv, "L5.b: mulDivUpRoundsUp with a=repaidUnits, b=lifTimesLltv, d=WAD^2 (MulDiv.spec)";
    require maxSeizedValue * lltv <= maxDebtDropBound * W => ghostMulDivUp(maxSeizedValue, lltv, W) <= maxDebtDropBound, "L5.c: mulDivCeilLeOfMulGe with a=maxSeizedValue, b=lltv, d=W, bound=maxDebtDropBound (MulDiv.spec)";

    // Linear glue, with no nested division:
    //   (a) collatValueDrop <= maxSeizedValue: from L2 (drop <= up(seizedOut,..)) and L1 (up(seizedOut,..) <= msv).
    //   (b) up(collatValueDrop,lltv,W) <= up(maxSeizedValue,lltv,W): L4 with (a).
    //   (c) up(maxSeizedValue,lltv,W) <= maxDebtDropBound: (L5.a scaled by lltv) chained through L5.b, then the W
    //       cancel, then L5.c.
    //   (d) curContrib - newContrib <= up(collatValueDrop,lltv,W) (L3) <= (b) <= (c) = maxDebtDropBound.

    ///// FINAL HEALTH GLUE /////
    // The RCF cap over-repays the gap: with repaidUnits == maxRepaid == ceil(gap*WAD^2/(WAD^2 - lif*lltv))
    // (Midnight.sol:699), maxRepaid*lif*lltv <= (maxRepaid - gap)*WAD^2 (axiomUpRoundsUp on gap), hence
    // maxDebtDropBound = ceil(maxRepaid*lif*lltv/WAD^2) <= maxRepaid - gap (axiomCeilLeOfMulGe). Combined with
    // the drop bound: newMaxDebt = maxDebt - drop >= debt - maxRepaid = newDebt.
    uint256 rcfDenominator = assert_uint256(S - lifTimesLltv);
    require axiomUpRoundsUp(gap, S, rcfDenominator), "proved in mulDivUpRoundsUp";
    uint256 repaidExcess = assert_uint256(repaidUnits - gap);
    require axiomCeilLeOfMulGe(repaidUnits, lifTimesLltv, S, repaidExcess), "proved in mulDivCeilLeOfMulGe";

    assert isHealthyNoBitmap(globalMarket, globalId, borrower);
}
