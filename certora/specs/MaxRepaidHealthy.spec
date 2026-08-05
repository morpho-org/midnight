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
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Summarize mulDivDown and mulDivUp deterministically; the tight rounding facts about them are proved
    // over concrete mulDiv in MulDiv.spec and injected below only at the specific instances the rule needs.
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

// Tight rounding facts proved over concrete mulDiv in MulDiv.spec. The rule assumes only the ground instances
// it uses, avoiding quantified background axioms.

// Proved in mulDivUpRoundsUp: a * b <= ceil(a * b / d) * d.
definition axiomUpRoundsUp(uint256 a, uint256 b, uint256 d) returns bool = d > 0 => a * b <= ghostMulDivUp(a, b, d) * d;

// Proved in mulDivCeilLeOfMulGe: a * b <= bound * d => ceil(a * b / d) <= bound.
definition axiomCeilLeOfMulGe(uint256 a, uint256 b, uint256 d, uint256 bound) returns bool = d > 0 && a * b <= bound * d => ghostMulDivUp(a, b, d) <= bound;

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
// The rule specializes this market to two collaterals.

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

/// RULE ///

// In a two-collateral market, liquidating at the amount computed by maxRepaidFor leaves the position healthy.
// The call uses normal mode and covers the strictly unhealthy and health-boundary cases.
rule liquidateAtCapRestoresHealth(env e, uint256 collateralIndex, address borrower, address receiver, address callback, bytes data) {
    Midnight.Market globalMarket = getGlobalMarket();

    require globalMarketCollateralLength == 1 || globalMarketCollateralLength == 2, "single- or two-collateral market";

    // No bad debt is realized, so liquidate does not reduce _position.debt before the RCF cap at
    // Midnight.sol:699 and maxRepaidFor reproduces that cap from the same debt (Rocq assumes no bad debt).
    require badDebtFor(globalMarket, globalId, borrower) == 0, "no bad debt realized";

    uint256 collatBefore = collateral(globalId, borrower, collateralIndex);
    uint256 debtBefore = debt(globalId, borrower);

    // maxRepaidFor reproduces the RCF cap at Midnight.sol:699. Passing that value to liquidate satisfies the
    // first disjunct of the RCF check at Midnight.sol:700-705, independently of the dust waiver.
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, borrower);

    // maxRepaidFor's non-reverting collateral lookup establishes collateralIndex < globalMarketCollateralLength.
    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);
    uint256 price = summaryPrice(globalMarket.collateralParams[collateralIndex].oracle);

    // Regime and guards under which liquidate at the RCF cap does not revert: the Rocq theorem's hypotheses plus
    // liquidate's own require guards. These are preconditions of the theorem, not a weakening of the conclusion.
    require e.msg.value == 0, "Midnight is not payable (liquidate is non-payable)";
    require currentContract.marketState[globalId].tickSpacing != 0, "market already created (touchMarket is a no-op)";
    require globalMarketLiquidatorGate == 0, "no liquidator gate (Midnight.sol:635)";
    require callback == 0, "no liquidate callback";
    require !liquidationLocked(globalId, borrower), "borrower not liquidation-locked (Midnight.sol:660)";
    require !isHealthyNoBitmap(globalMarket, globalId, borrower), "strictly unhealthy: debt > maxDebt (Midnight.sol:661)";
    require lltv < WAD(), "RCF is active only for lltv < WAD (Midnight.sol:695)";
    require lif * lltv <= 999 * 10 ^ 15 * WAD(), "maxLif * lltv <= 0.999 * WAD^2: RCF denominator positive (Midnight.sol:698)";
    require price > 0, "positive liquidated-collateral price";

    // No-overflow regime (Midnight LIVENESS: liquidate can revert on overflow). Every checked product in
    // liquidate's maxDebt / badDebt / seize / RCF computations stays within 256 bits, and every maxLif
    // denominator is positive, so no summarized mulDiv takes its overflow / d == 0 revert branch.
    require lif > 0, "positive maxLif for the liquidated collateral (created-market invariant)";
    require lif <= 2 * WAD(), "maxLif <= 2 * WAD (Midnight.sol:810)";
    require collatBefore * price + ORACLE_PRICE_SCALE() <= max_uint256, "collateral value (index) fits 256 bits";
    require ghostMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE()) * lltv <= max_uint256, "maxDebt term (index) fits 256 bits";
    require ghostMulDivUp(collatBefore, price, ORACLE_PRICE_SCALE()) * WAD() + lif <= max_uint256, "badDebt term (index) fits 256 bits";
    require repaidUnits * lif <= max_uint256, "maxSeizedValue product fits 256 bits";
    require ghostMulDivDown(repaidUnits, lif, WAD()) * ORACLE_PRICE_SCALE() <= max_uint256, "seized value fits 256 bits";

    // The other collateral's contribution to maxDebt exists only in a two-collateral market (the Rocq
    // otherCollatContribution); in a single-collateral market it is 0. Its no-overflow bounds are needed only
    // when liquidate's loop actually visits that collateral.
    uint256 otherContrib = 0;
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
        otherContrib = ghostMulDivDown(ghostMulDivDown(otherCollatBefore, otherPrice, ORACLE_PRICE_SCALE()), otherLltv, WAD());
    }

    // Exactly the market's collaterals [0, globalMarketCollateralLength) are activated, so liquidate's bitmap
    // maxDebt loop (Midnight.sol:645) ranges over the same indices as the array-based maxRepaidFor /
    // isHealthyNoBitmap. Covers both the single- and two-collateral markets.
    uint128 bitmap = collateralBitmap(globalId, borrower);
    require forall uint256 bit. summaryGetBit(bitmap, bit) <=> bit < globalMarketCollateralLength, "exactly the market's collaterals are activated";

    // Seized collateral (Midnight.sol:692) does not exceed the position collateral (Midnight.sol:708 subtraction).
    require collatBefore >= ghostMulDivDown(ghostMulDivDown(repaidUnits, lif, WAD()), ORACLE_PRICE_SCALE(), price), "seized <= collateral";

    // No overflow of the market's withdrawable when repaid units are credited (Midnight.sol:713).
    require currentContract.marketState[globalId].withdrawable + repaidUnits <= max_uint128, "withdrawable credit does not overflow";

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate@withrevert(e, globalMarket, collateralIndex, 0, repaidUnits, borrower, false, receiver, callback, data);

    // Liquidating at the RCF cap succeeds: repaidUnits == maxRepaid satisfies the RCF require (Midnight.sol:700-705).
    assert !lastReverted;

    uint256 collatAfter = assert_uint256(collatBefore - seizedOut);

    /// MAX-DEBT DROP BOUND ///
    // Establish curContrib - newContrib <= maxDebtDropBound. At Midnight.sol:692, liquidate computes
    // seizedOut = floor(floor(repaidUnits * lif / WAD) * ORACLE_PRICE_SCALE / price), matching the ghost terms
    // below. Each require is one ground instance of a rule proved in MulDiv.spec.

    uint256 maxSeizedValue = ghostMulDivDown(repaidUnits, lif, WAD());

    // By Midnight.sol:692, seizedOut == ghostMulDivDown(maxSeizedValue, ORACLE_PRICE_SCALE(), price).
    uint256 curCollatValue = ghostMulDivDown(collatBefore, price, ORACLE_PRICE_SCALE());
    uint256 newCollatValue = ghostMulDivDown(collatAfter, price, ORACLE_PRICE_SCALE());

    uint256 curContrib = ghostMulDivDown(curCollatValue, lltv, WAD());
    uint256 newContrib = ghostMulDivDown(newCollatValue, lltv, WAD());

    uint256 lifTimesLltv = assert_uint256(lif * lltv);
    uint256 maxDebtDropBound = ghostMulDivUp(repaidUnits, lifTimesLltv, WAD_SQUARED());

    require price > 0 => ghostMulDivUp(seizedOut, price, ORACLE_PRICE_SCALE()) <= maxSeizedValue, "L1: mulDivInverseUpDown with a=maxSeizedValue, b=ORACLE_PRICE_SCALE, d=price (MulDiv.spec)";
    require curCollatValue <= newCollatValue + ghostMulDivUp(seizedOut, price, ORACLE_PRICE_SCALE()), "L2: mulDivAddDownUp with a1=collatAfter, a2=seizedOut, b=price, d=ORACLE_PRICE_SCALE (MulDiv.spec)";
    require curCollatValue <= newCollatValue + maxSeizedValue => curContrib <= newContrib + ghostMulDivUp(maxSeizedValue, lltv, WAD()), "L3: mulDivDownBoundedIncrease with a1=curCollatValue, a2=newCollatValue, delta=maxSeizedValue, b=lltv, d=WAD (MulDiv.spec)";
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
    require axiomUpRoundsUp(gap, WAD_SQUARED(), rcfDenominator), "proved in mulDivUpRoundsUp";
    uint256 repaidExcess = assert_uint256(repaidUnits - gap);
    require axiomCeilLeOfMulGe(repaidUnits, lifTimesLltv, WAD_SQUARED(), repaidExcess), "proved in mulDivCeilLeOfMulGe";

    assert isHealthyNoBitmap(globalMarket, globalId, borrower);
}
