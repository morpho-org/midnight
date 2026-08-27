// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function debt(bytes32 id, address user) external returns (uint128) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function maxRepaidFor(Midnight.Market, bytes32, uint256, address) external returns (uint256) envfree;
    function badDebtFor(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;

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
    // mulDiv: the ghosts are arbitrary, and the summaries reproduce exactly the revert condition of the real
    // mulDiv, so every real mulDiv behaviour is still allowed. All the arithmetic the rule actually needs is
    // required explicitly below, one ground instance per rule proved over the concrete mulDiv in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // maxLif is deterministic for each (lltv, liquidationCursor) pair.
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // Token transfers move external ERC20 balances only, never the borrower's position storage, so summarizing
    // them as non-reverting no-ops is sound for this direction. The liquidator gate and callback are ruled out by
    // the liquidatorGate == 0 and callback == 0 preconditions, so canLiquidate / onLiquidate are never called.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.transferFrom(address from, address to, uint256 amount) external => NONDET;
    function _.transfer(address to, uint256 amount) external => NONDET;
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

definition WAD_SQUARED() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256;

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256;

// Deterministic overflow: the real mulDiv reverts iff d == 0 or the checked product overflows 256 bits. Modeling
// that exact condition (rather than a nondeterministic overflow flag) is what makes revert-freedom provable.
function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || to_mathint(a) * to_mathint(b) > max_uint256) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || to_mathint(a) * to_mathint(b) + (to_mathint(d) - 1) > max_uint256) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

// Pin every field that contributes to the market id, making the toId summary deterministic and injective.

persistent ghost address globalMarketLoanToken;

persistent ghost uint256 globalMarketChainId;

// At most two collaterals is not a restriction on the result. Liquidating touches a single collateral, so the
// whole contribution of every other collateral to maxDebt enters the reasoning as one arbitrary non-negative
// value, and one extra collateral with an arbitrary amount, price and LLTV already realizes every such value.
// The second collateral therefore plays the role of the arbitrary otherCollatContribution of the Rocq proof,
// and a market with more collaterals is covered by the same argument.
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

/// RULE ///

// RESTORATION. In a single- or two-collateral, RCF-active, no-bad-debt market, liquidating at the amount
// computed by maxRepaidFor leaves the borrower healthy. The liquidate call is PLAIN (normal mode), so only
// non-reverting executions are asserted healthy; the companion rule liquidateAtCapDoesNotRevert proves that the
// liquidation actually succeeds. Covers the strictly-unhealthy case (the boundary is healthy already).
// See the globalMarketCollateralLength axiom for why at most two collaterals is general enough.
rule liquidateAtCapRestoresHealth(env e, uint256 collateralIndex, address borrower, address receiver, address callback, bytes data) {
    Midnight.Market globalMarket = getGlobalMarket();

    require globalMarketCollateralLength == 1 || globalMarketCollateralLength == 2, "single- or two-collateral market";

    // No bad debt is realized, so liquidate does not reduce the position debt before computing the RCF cap, and
    // maxRepaidFor reproduces that cap from the same debt (Rocq assumes no bad debt).
    require badDebtFor(globalMarket, globalId, borrower) == 0, "no bad debt realized";

    uint256 collatBefore = collateral(globalId, borrower, collateralIndex);
    uint256 debtBefore = debt(globalId, borrower);

    // This rule checks that using `repaidUnits == maxRepaid` is enough to put the account healthy. This means
    // that the RCF doesn't prevent to put the position back to health.
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, borrower);

    // maxRepaidFor's non-reverting collateral lookup establishes collateralIndex < globalMarketCollateralLength.
    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);
    uint256 price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // Restoration hypotheses (Rocq): strictly unhealthy, RCF active (lltv < WAD) with a positive RCF cap
    // denominator, and a positive price. No revert-clearing guards are needed here: the plain call keeps only
    // the non-reverting executions.
    require !isHealthyNoBitmap(globalMarket, globalId, borrower), "strictly unhealthy: debt > maxDebt";
    require lltv < WAD(), "RCF is active only for lltv < WAD";
    require lif * lltv <= 999 * 10 ^ 15 * WAD(), "maxLif * lltv <= 0.999 * WAD^2: RCF denominator positive";
    require price > 0, "positive liquidated-collateral price";

    // The other collateral's contribution to maxDebt exists only in a two-collateral market (the Rocq
    // otherCollatContribution); in a single-collateral market it is 0.
    uint256 otherContrib = 0;
    if (globalMarketCollateralLength == 2) {
        uint256 otherIndex = assert_uint256(1 - collateralIndex);
        uint256 otherCollatBefore = collateral(globalId, borrower, otherIndex);
        uint256 otherLltv = globalMarketCollateralLLTV[otherIndex];
        uint256 otherPrice = summaryPrice(globalMarket.collateralParams[otherIndex].oracle);
        otherContrib = ghostMulDivDown(ghostMulDivDown(otherCollatBefore, otherPrice, ORACLE_PRICE_SCALE()), otherLltv, WAD());
    }

    // The activated collaterals are exactly [0, globalMarketCollateralLength), so liquidate's bitmap maxDebt /
    // badDebt loop ranges over the same indices as the array-based maxRepaidFor / isHealthyNoBitmap. Pinned
    // with ground facts per index (no ghost-bounded quantifier, which the solver would not instantiate at the
    // loop's concrete bits) for each supported market size.
    uint128 bitmap = collateralBitmap(globalId, borrower);
    require summaryGetBit(bitmap, 0), "collateral 0 is activated";
    if (globalMarketCollateralLength == 2) {
        require summaryGetBit(bitmap, 1), "collateral 1 is activated (two-collateral market)";
        require forall uint256 otherBit. otherBit != 0 && otherBit != 1 => !summaryGetBit(bitmap, otherBit), "only the two collaterals are activated";
    } else {
        require forall uint256 otherBit. otherBit != 0 => !summaryGetBit(bitmap, otherBit), "single-collateral: only collateral 0 is activated";
    }

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate(e, globalMarket, collateralIndex, 0, repaidUnits, borrower, false, receiver, callback, data);

    uint256 collatAfter = assert_uint256(collatBefore - seizedOut);

    /// MAX-DEBT DROP BOUND ///
    // Establish curContrib - newContrib <= maxDebtDropBound. When it seizes, liquidate computes
    // seizedOut = floor(floor(repaidUnits * lif / WAD) * ORACLE_PRICE_SCALE / price), matching the ghost terms
    // below. Each require is one ground instance of a rule proved in MulDiv.spec.

    uint256 maxSeizedValue = ghostMulDivDown(repaidUnits, lif, WAD());

    // By that same computation, seizedOut == ghostMulDivDown(maxSeizedValue, ORACLE_PRICE_SCALE(), price).
    uint256 curCollatValue = ghostMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 newCollatValue = ghostMulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());

    uint256 curContrib = ghostMulDivDown(curCollatValue, lltv, WAD());
    uint256 newContrib = ghostMulDivDown(newCollatValue, lltv, WAD());

    uint256 lifTimesLltv = assert_uint256(lif * lltv);
    uint256 maxDebtDropBound = ghostMulDivUp(repaidUnits, lifTimesLltv, WAD_SQUARED());

    require price > 0 => ghostMulDivUp(seizedOut, price, ORACLE_PRICE_SCALE()) <= maxSeizedValue, "L1: mulDivInverseUpDown with a=maxSeizedValue, b=ORACLE_PRICE_SCALE, d=price (MulDiv.spec)";
    require curCollatValue <= newCollatValue + ghostMulDivUp(seizedOut, price, ORACLE_PRICE_SCALE()), "L2: mulDivAddDownUp with a1=collatAfter, a2=seizedOut, b=price, d=ORACLE_PRICE_SCALE (MulDiv.spec)";
    require curCollatValue <= newCollatValue + maxSeizedValue => curContrib <= newContrib + ghostMulDivUp(maxSeizedValue, lltv, WAD()), "L3: mulDivMonotoneA then mulDivAddDownUp with a1=newCollatValue, a2=maxSeizedValue, b=lltv, d=WAD (MulDiv.spec)";
    require ghostMulDivUp(maxSeizedValue, lltv, WAD()) <= maxDebtDropBound, "L4: mulDivDownUpComposition with a=repaidUnits, b=lif, c=lltv, d=WAD (MulDiv.spec)";

    // L1-L2 bound the collateral-value decrease by maxSeizedValue. L3 transports that bound through the LLTV
    // contribution, and L4 bounds the composed rounding by maxDebtDropBound.

    /// FINAL HEALTH BOUND ///
    // repaidUnits is ceil(gap * WAD^2 / (WAD^2 - lif * lltv)). The two rounding facts below imply
    // maxDebtDropBound <= repaidUnits - gap. Therefore the new max debt falls by no more than the amount
    // repaid in excess of the old health gap.
    uint256 maxDebtBefore = require_uint256(curContrib + otherContrib);

    // Safe: maxRepaidFor's non-reverting subtraction establishes debtBefore >= maxDebtBefore.
    uint256 gap = require_uint256(debtBefore - maxDebtBefore);
    uint256 rcfDenominator = assert_uint256(WAD_SQUARED() - lifTimesLltv);
    require rcfDenominator > 0 => gap * WAD_SQUARED() <= ghostMulDivUp(gap, WAD_SQUARED(), rcfDenominator) * rcfDenominator, "proved in mulDivUpRoundsUp";
    uint256 repaidExcess = assert_uint256(repaidUnits - gap);
    require repaidUnits * lifTimesLltv <= repaidExcess * WAD_SQUARED() => ghostMulDivUp(repaidUnits, lifTimesLltv, WAD_SQUARED()) <= repaidExcess, "proved in mulDivCeilLeOfMulGe";

    assert isHealthyNoBitmap(globalMarket, globalId, borrower);
}

// LIVENESS. In the same single- or two-collateral, RCF-active, no-bad-debt regime, liquidating at maxRepaidFor
// does not revert. Mirrors LossFactor.spec's liquidateLossFactorDoesNotRevert. This rule proves only no-revert;
// the restoration of health is proved by liquidateAtCapRestoresHealth.
rule liquidateAtCapDoesNotRevert(env e, uint256 collateralIndex, address borrower, address receiver, address callback, bytes data) {
    Midnight.Market globalMarket = getGlobalMarket();

    require globalMarketCollateralLength == 1 || globalMarketCollateralLength == 2, "single- or two-collateral market";

    // No bad debt is realized, so the bad-debt socialization block of liquidate is skipped.
    require badDebtFor(globalMarket, globalId, borrower) == 0, "no bad debt realized";

    uint256 collatBefore = collateral(globalId, borrower, collateralIndex);
    uint256 debtBefore = debt(globalId, borrower);
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, borrower);

    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);
    uint256 price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // liquidate's own require guards + RCF-active regime.
    require e.msg.value == 0, "Midnight is not payable (liquidate is non-payable)";
    require currentContract.marketState[globalId].tickSpacing != 0, "market already created (touchMarket is a no-op)";
    require globalMarketLiquidatorGate == 0, "no liquidator gate";
    require callback == 0, "no liquidate callback";
    require !liquidationLocked(globalId, borrower), "borrower not liquidation-locked";
    require !isHealthyNoBitmap(globalMarket, globalId, borrower), "strictly unhealthy: debt > maxDebt";
    require lltv < WAD(), "RCF is active only for lltv < WAD";
    require lif * lltv <= 999 * 10 ^ 15 * WAD(), "maxLif * lltv <= 0.999 * WAD^2: RCF denominator positive";
    require price > 0, "positive liquidated-collateral price";

    // No-overflow regime (Midnight LIVENESS: the checked mulDiv reverts on 256-bit overflow). Every checked
    // product in liquidate's maxDebt / badDebt / seize / RCF computations stays within 256 bits, and every
    // maxLif denominator is positive, so no summarized mulDiv takes its overflow / d == 0 revert branch.
    require lif > 0, "positive maxLif for the liquidated collateral (created-market invariant)";
    require lif <= 2 * WAD(), "maxLif <= 2 * WAD";
    require collatBefore * price + ORACLE_PRICE_SCALE() <= max_uint256, "collateral value (index) fits 256 bits";
    require ghostMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()) * lltv <= max_uint256, "maxDebt term (index) fits 256 bits";
    require ghostMulDivUp(collatBefore, price, ORACLE_PRICE_SCALE()) * WAD() + lif <= max_uint256, "badDebt term (index) fits 256 bits";
    require repaidUnits * lif <= max_uint256, "maxSeizedValue product fits 256 bits";
    require ghostMulDivDown(repaidUnits, lif, WAD()) * ORACLE_PRICE_SCALE() <= max_uint256, "seized value fits 256 bits";

    // The other collateral's no-overflow bounds are needed only when liquidate's loop visits that collateral.
    if (globalMarketCollateralLength == 2) {
        uint256 otherIndex = assert_uint256(1 - collateralIndex);
        uint256 otherCollatBefore = collateral(globalId, borrower, otherIndex);
        uint256 otherLltv = globalMarketCollateralLLTV[otherIndex];
        uint256 otherPrice = summaryPrice(globalMarket.collateralParams[otherIndex].oracle);
        uint256 maxLifOther = maxLifGhost(otherLltv, globalMarketCollateralLiquidationCursor[otherIndex]);
        require maxLifOther > 0, "positive maxLif for the other collateral (created-market invariant)";
        require otherCollatBefore * otherPrice + ORACLE_PRICE_SCALE() <= max_uint256, "collateral value (other) fits 256 bits";
        require ghostMulDivDown(otherCollatBefore, otherPrice, ORACLE_PRICE_SCALE()) * otherLltv <= max_uint256, "maxDebt term (other) fits 256 bits";
        require ghostMulDivUp(otherCollatBefore, otherPrice, ORACLE_PRICE_SCALE()) * WAD() + maxLifOther <= max_uint256, "badDebt term (other) fits 256 bits";
    }

    // The activated collaterals are exactly [0, globalMarketCollateralLength): liquidate's bitmap loop ranges
    // over the same indices as maxRepaidFor / badDebtFor, and the liquidatable check reads the same maxDebt.
    // Ground-fact pin per supported market size.
    uint128 bitmap = collateralBitmap(globalId, borrower);
    require summaryGetBit(bitmap, 0), "collateral 0 is activated";
    if (globalMarketCollateralLength == 2) {
        require summaryGetBit(bitmap, 1), "collateral 1 is activated (two-collateral market)";
        require forall uint256 otherBit. otherBit != 0 && otherBit != 1 => !summaryGetBit(bitmap, otherBit), "only the two collaterals are activated";
    } else {
        require forall uint256 otherBit. otherBit != 0 => !summaryGetBit(bitmap, otherBit), "single-collateral: only collateral 0 is activated";
    }

    // The seized collateral does not exceed the position collateral, so liquidate's collateral subtraction
    // does not underflow. Left as an explicit hypothesis pending review; implied by no bad debt + the
    // maxRepaidFor debt clamp.
    require collatBefore >= ghostMulDivDown(ghostMulDivDown(repaidUnits, lif, WAD()), ORACLE_PRICE_SCALE(), price), "seized <= collateral";

    // No overflow of the market's withdrawable when the repaid units are credited.
    require currentContract.marketState[globalId].withdrawable + repaidUnits <= max_uint128, "withdrawable credit does not overflow";

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate@withrevert(e, globalMarket, collateralIndex, 0, repaidUnits, borrower, false, receiver, callback, data);

    // Liquidating at the RCF cap succeeds: repaidUnits <= maxRepaid satisfies liquidate's RCF require.
    assert !lastReverted, "liquidating at the RCF cap does not revert";
}
