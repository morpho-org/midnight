// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function collateral(bytes32, address, uint256) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // No price update.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // All external calls are assumed non-reentrant / non-reverting: we reason about the function bodies for safety properties.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.isRatified(Midnight.Offer, bytes, address) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
}

/// SUMMARIES / GHOSTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

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

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// RULES ///

// liquidate realizes the bad debt and doesn't create new bad debt: the recomputed realizable bad debt is exactly 0 after a liquidate.
rule liquidateRealizesBadDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);
    mathint seizedAssetsOut;

    mathint price = summaryPrice(market.collateralParams[collateralIndex].oracle);
    mathint maxLif = maxLifGhost(market.collateralParams[collateralIndex].lltv, market.collateralParams[collateralIndex].liquidationCursor);

    if (repaidUnits == 0) {
        seizedAssetsOut = seizedAssets;
    } else {
        seizedAssetsOut = ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price);
    
        // Monotone in the first argument (proven in MulDiv.spec as mulDivMonotoneA).
        require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d), "axiom";
    
        // Monotone in the second argument (proven in MulDiv.spec as mulDivMonotoneB).
        require forall mathint a. forall mathint b1. forall mathint b2. forall mathint d. 0 <= a && 0 <= b1 && b1 <= b2 && 0 < d => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d), "axiom";
    
        // proven in MulDiv.spec as mulDivInverseUpDown:
        //   mulDivUp(mulDivDown(a,b,d),d,b) <= a
        require repaidUnits >= 0 && maxLif > 0 && WAD() > 0 => ghostMulDivUp(ghostMulDivDown(repaidUnits, maxLif, WAD()), WAD(), maxLif) <= repaidUnits, "axiom";
    
        // proven in MulDiv.spec as mulDivInverseUpDown:
        //   mulDivUp(mulDivDown(a,b,d),d,b) <= a
        require ghostMulDivDown(repaidUnits, maxLif, WAD()) >= 0 && ORACLE_PRICE_SCALE() > 0 && price > 0 => ghostMulDivUp(ghostMulDivDown(ghostMulDivDown(repaidUnits, maxLif, WAD()), ORACLE_PRICE_SCALE(), price), price, ORACLE_PRICE_SCALE()) <= ghostMulDivDown(repaidUnits, maxLif, WAD()), "axiom";
    }

    mathint collateralAfter = collateral(id, borrower, collateralIndex) - seizedAssetsOut;

    // Monotone in the first argument (proven in MulDiv.spec as mulDivMonotoneA).
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d), "axiom";

    // Monotone in the third argument (proven in MulDiv.spec as mulDivMonotoneD).
    require forall mathint a. forall mathint b. forall mathint d1. forall mathint d2. 0 <= a && 0 <= b && 0 < d1 && d1 <= d2 => ghostMulDivUp(a, b, d2) <= ghostMulDivUp(a, b, d1), "axiom";

    // Zero collateral values to zero (proven in MulDiv.spec as mulDivZero).
    require ORACLE_PRICE_SCALE() > 0 => ghostMulDivUp(0, price, ORACLE_PRICE_SCALE()) == 0, "axiom";

    // Zero collateral values to zero (proven in MulDiv.spec as mulDivZero).
    require maxLif > 0 => ghostMulDivUp(0, WAD(), maxLif) == 0, "axiom";

    // proven in MulDiv.spec as mulDivAddUpUp:
    //   mulDivUp(a1 + a2, b, d) <= mulDivUp(a1, b, d) + mulDivUp(a2, b, d).
    require collateralAfter >= 0 && seizedAssetsOut >= 0 && price >= 0 && ORACLE_PRICE_SCALE() > 0 => ghostMulDivUp(collateralAfter + seizedAssetsOut, price, ORACLE_PRICE_SCALE()) <= ghostMulDivUp(collateralAfter, price, ORACLE_PRICE_SCALE()) + ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), "axiom";

    // proven in MulDiv.spec as mulDivAddUpUp:
    //   mulDivUp(a1 + a2, b, d) <= mulDivUp(a1, b, d) + mulDivUp(a2, b, d).
    require ghostMulDivUp(collateralAfter, price, ORACLE_PRICE_SCALE()) >= 0 && ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()) >= 0 && WAD() >= 0 && maxLif > 0 => ghostMulDivUp(ghostMulDivUp(collateralAfter, price, ORACLE_PRICE_SCALE()) + ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), WAD(), maxLif) <= ghostMulDivUp(ghostMulDivUp(collateralAfter, price, ORACLE_PRICE_SCALE()), WAD(), maxLif) + ghostMulDivUp(ghostMulDivUp(seizedAssetsOut, price, ORACLE_PRICE_SCALE()), WAD(), maxLif), "axiom";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert realizableBadDebt(market, id, borrower) == 0;
}

// liquidating one position does not increase the realizable bad debt of a different position.
rule liquidateDoesNotIncreaseOtherRealizableBadDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, Midnight.Market measuredMarket, address measuredBorrower) {
    bytes32 id = summaryToId(market);
    bytes32 measuredId = summaryToId(measuredMarket);

    require measuredId != id || measuredBorrower != borrower;

    uint256 rbdBefore = realizableBadDebt(measuredMarket, measuredId, measuredBorrower);

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert realizableBadDebt(measuredMarket, measuredId, measuredBorrower) <= rbdBefore;
}
