// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";

// On-contract version of the Rocq theorem max_repaid_liquidation_leaves_healthy (rocq/maxRepaidHealthy.v):
// in the RCF-active regime (!postMaturityMode && lltv < WAD), liquidating an unhealthy position at the RCF
// cap repaid = maxRepaid (see src/Midnight.sol:699) restores health (newDebt <= newMaxDebt, newDebt >= 0).
// This is the RESTORATION direction; Healthiness.spec proves the PRESERVATION direction.
// Single-collateral first: the Rocq otherCollatContribution is 0 here (the market has one collateral).

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

    // Summarize mulDivDown and mulDivUp deterministically; the axioms about them are proved in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // maxLif is recomputed on the fly from (lltv, liquidationCursor); its lltv * maxLif <= WAD * WAD bound is
    // assumed below (see lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec).
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // No reentrancy is modeled for this direction: transfers move external ERC20 balances only, never the
    // borrower's position storage, so summarizing them as no-ops is sound. The callback is disabled below.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.transferFrom(address from, address to, uint256 amount) external => NONDET;
    function _.transfer(address to, uint256 amount) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
    function _.onLiquidate(address liquidator, bytes32 id, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, bytes data, uint256 badDebt) external => NONDET;
}

/// SUMMARY ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

/* Axioms used to reconstruct the Rocq integer-division argument.
   The two cheap rounding facts are proved over concrete mulDiv in MulDiv.spec. The single hard nonlinear step
   (the LLTV-weighted maxDebt drop bound) is delegated to axiomMaxDebtDrop, machine-checked over the integers in
   Rocq; assuming it here keeps the on-contract goal linear, so the prover does not have to rediscover the chain. */

/* proved in mulDivUpRoundsUp: a*b <= ceil(a*b/d)*d (Rocq ceil_div_mul_ge). */
definition axiomUpRoundsUp(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 && d > 0 => a * b <= ghostMulDivUp(a, b, d) * d;

/* proved in mulDivCeilLeOfMulGe: a*b <= bound*d => ceil(a*b/d) <= bound (Rocq ceil_div_le_of_mul_ge). */
definition axiomCeilLeOfMulGe(mathint a, mathint b, mathint d, mathint bound) returns bool = a >= 0 && b >= 0 && d > 0 && a * b <= bound * d => ghostMulDivUp(a, b, d) <= bound;

/* Rocq max_debt_contribution_drop_bound (rocq/maxRepaidHealthy.v:162), the one hard nonlinear step: when
   seized is the L692 seizedAssets = floor(floor(maxRepaid*lif/WAD)*OPS/price), the LLTV-weighted maxDebt
   contribution drops by at most ceil(maxRepaid*lif*lltv/WAD^2). Proved over the integers in Rocq; the Solidity
   quantities are shown equal to its variables in the rule below, and the CVL bounds wire it to on-chain health. */
definition axiomMaxDebtDrop(mathint collat, mathint seized, mathint price, mathint lltv, mathint maxRepaid, mathint lif) returns bool = price > 0 && collat >= 0 && 0 <= seized && seized <= collat && lltv >= 0 && maxRepaid >= 0 && lif >= 0 && seized == ghostMulDivDown(ghostMulDivDown(maxRepaid, lif, WAD()), ORACLE_PRICE_SCALE(), price) => ghostMulDivDown(ghostMulDivDown(collat, price, ORACLE_PRICE_SCALE()), lltv, WAD()) - ghostMulDivDown(ghostMulDivDown(collat - seized, price, ORACLE_PRICE_SCALE()), lltv, WAD()) <= ghostMulDivUp(maxRepaid, lif * lltv, WAD() * WAD());

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
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

persistent ghost address globalBorrower;

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
function maxDebtContribution(uint256 collat, mathint price, uint256 lltv) returns mathint {
    return ghostMulDivDown(ghostMulDivDown(collat, price, ORACLE_PRICE_SCALE()), lltv, WAD());
}

//// RULE //////

// Liquidating an unhealthy position at the RCF cap restores its health, in the single-collateral,
// RCF-active (!postMaturityMode && lltv < WAD), no-bad-debt regime. This is the on-contract analog of the
// Rocq theorem max_repaid_liquidation_leaves_healthy, maxRepaid < debt case (newDebt = debt - maxRepaid > 0).
rule liquidateAtCapRestoresHealth(env e, uint256 collateralIndex, address receiver, address callback, bytes data) {
    // Post-state health is read bitmap-free; combined with single-collateral this avoids bitmap iteration.
    Midnight.Market globalMarket = getGlobalMarket();

    // Single collateral: the Rocq otherCollatContribution is 0.
    require globalMarketCollateralLength == 1, "single-collateral market";
    require collateralIndex == 0, "the only collateral index";

    uint256 lltv = globalMarketCollateralLLTV[collateralIndex];
    uint256 lif = maxLifGhost(lltv, globalMarketCollateralLiquidationCursor[collateralIndex]);

    // RCF-active regime.
    require lltv < WAD(), "RCF is active only for lltv < WAD";

    // maxLif * lltv <= 0.999 * WAD * WAD is enforced at market creation for lltv < WAD (see Midnight.sol:698,
    // createdMarketsRespectMaxLifBound in CreatedMarkets.spec); it makes the L699 denominator strictly positive.
    require lltv * lif <= 999 * 10 ^ 15 * WAD(), "maxLif * lltv <= 0.999 * WAD * WAD";

    // lltv * maxLif <= WAD * WAD (see lifTimesLltvIsLessThanOrEqualToOne in ExactMath.spec).
    require lltv * lif <= WAD() * WAD(), "lltv * maxLif <= WAD * WAD";

    address oracle = globalMarket.collateralParams[collateralIndex].oracle;
    mathint price = summaryPrice(oracle);

    // 0 < price (Rocq hypothesis); otherwise the mulDiv by price reverts and the case is vacuous.
    require price > 0, "positive price";

    // Single-collateral bitmap: only collateralIndex is activated, so the liquidate maxDebt loop and the
    // array-based maxRepaidFor / isHealthyNoBitmap all range over exactly {collateralIndex}.
    uint128 bitmap = collateralBitmap(globalId, globalBorrower);
    require summaryGetBit(bitmap, collateralIndex), "collateral is activated (see nonZeroCollateralsAreActivated)";
    require forall uint256 otherBit. otherBit != collateralIndex => !summaryGetBit(bitmap, otherBit), "single-collateral: only collateralIndex activated";

    // Borrower must not be liquidation-locked (see Midnight.sol:660).
    require !liquidationLocked(globalId, globalBorrower), "borrower not locked";

    // No callback, so onLiquidate is skipped and no reentrancy occurs.
    require callback == 0, "no liquidate callback";

    // No liquidator gate, so canLiquidate is skipped (see Midnight.sol:635-638).
    require globalMarketLiquidatorGate == 0, "no liquidator gate";

    // Market is already created, so touchMarket is a no-op that returns globalId.
    require currentContract.marketState[globalId].tickSpacing != 0, "market already created";

    // No bad debt is realized: liquidate does not reduce _position.debt before the L699 cap computation, so the
    // debt used at L699 equals the pre-liquidation debt read by maxRepaidFor (Rocq assumes no bad-debt path).
    require badDebtFor(globalMarket, globalId, globalBorrower) == 0, "no bad debt realized";

    // Unhealthy pre-state: maxDebt < debt (Rocq maxDebt <= debt with the strict RCF trigger of Midnight.sol:661).
    require !isHealthyNoBitmap(globalMarket, globalId, globalBorrower), "unhealthy before liquidation";

    uint256 collatBefore = collateral(globalId, globalBorrower, collateralIndex);
    uint256 debtBefore = debt(globalId, globalBorrower);

    // Pin repaid to the RCF cap. maxRepaidFor reproduces Midnight.sol:699 exactly, so repaidUnits equals the
    // maxRepaid recomputed inside liquidate and the RCF require (Midnight.sol:700-705) passes on its first
    // disjunct (repaidUnits <= maxRepaid), independently of the dust waiver.
    uint256 repaidUnits = maxRepaidFor(globalMarket, globalId, collateralIndex, globalBorrower);

    // Interesting case: maxRepaid < debt (repaid = maxRepaid, newDebt = debt - maxRepaid > 0). The maxRepaid >= debt
    // case gives repaid = debt, newDebt = 0, which is trivially healthy.
    require repaidUnits < debtBefore, "maxRepaid < debt case";

    uint256 seizedOut;
    uint256 repaidOut;
    seizedOut, repaidOut = liquidate(e, globalMarket, collateralIndex, 0, repaidUnits, globalBorrower, false, receiver, callback, data);

    // The seized collateral must not exceed the current collateral (Rocq seizedAssets <= collat); otherwise
    // liquidate reverts independently of the RCF mechanism, so this does not narrow the generality.
    require collatBefore >= seizedOut, "seized <= collateral";

    // gap = debt - maxDebt > 0 (the position is unhealthy). Both are the single-collateral quantities that
    // liquidate uses internally: maxDebt at L699 and debt (unchanged, since no bad debt) equal these.
    mathint gap = debtBefore - maxDebtContribution(collatBefore, price, lltv);

    // Three axioms close the goal with only linear glue (see rocq/maxRepaidHealthy.v, maxRepaid < debt case):
    // the maxDebt drop is bounded by ceil(maxRepaid*lif*lltv/WAD^2) (axiomMaxDebtDrop), the RCF cap over-repays
    // the gap so maxRepaid*lif*lltv <= (maxRepaid - gap)*WAD^2 (axiomUpRoundsUp), hence that ceil is at most
    // maxRepaid - gap (axiomCeilLeOfMulGe); so newMaxDebt = maxDebt - drop >= debt - maxRepaid = newDebt.
    require axiomMaxDebtDrop(collatBefore, seizedOut, price, lltv, repaidUnits, lif), "Rocq max_debt_contribution_drop_bound";
    require axiomUpRoundsUp(gap, WAD() * WAD(), WAD() * WAD() - lif * lltv), "proved in mulDivUpRoundsUp (Rocq ceil_div_mul_ge)";
    require axiomCeilLeOfMulGe(repaidUnits, lif * lltv, WAD() * WAD(), repaidUnits - gap), "proved in mulDivCeilLeOfMulGe (Rocq ceil_div_le_of_mul_ge)";

    // newDebt >= 0 and newDebt <= newMaxDebt, i.e. the position is healthy after liquidation.
    assert isHealthyNoBitmap(globalMarket, globalId, globalBorrower), "position is healthy after liquidation at the RCF cap";
}
