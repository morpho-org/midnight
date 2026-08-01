// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function realizableBadDebt(Midnight.Market, bytes32, address) external returns (uint256) envfree;
    function debt(bytes32, address) external returns (uint128) envfree;
    function totalUnits(bytes32) external returns (uint128) envfree;
    function liquidationLocked(bytes32, address) external returns (bool) envfree;
    function tickSpacing(bytes32) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);

    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Safe because the protocol doesn't use `toMarket`
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Over-approximate the following functions.
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
    function maxLif(uint256 lltv, uint256 liquidationCursor) internal returns (uint256) => maxLifGhost(lltv, liquidationCursor);

    // All external calls are assumed non-reentrant / non-reverting: we reason about the function bodies for safety properties.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
}

/// SUMMARIES / GHOSTS ///

definition WAD() returns uint256 = 10 ^ 18;

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

persistent ghost maxLifGhost(uint256, uint256) returns uint256;

persistent ghost summaryPrice(address) returns uint256;

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

// No non-liquidate function may increase realizableBadDebt of a position.
rule realizableBadDebtCannotIncrease(env e, method f, calldataarg args, Midnight.Market market, address borrower) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    bytes32 id = summaryToId(market);

    // if seller is locked, they can create a position with bad debt.  In that case the position
    // must be healthy when the lock is removed later and no bad debt can be realized.
    require !liquidationLocked(id, borrower), "scope out the re-entrant case";

    // mulDivUp is monotone in the first argument (proven in MulDiv.spec as mulDivMonotoneA).
    require forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. 0 <= a1 && a1 <= a2 && 0 <= b && 0 < d => ghostMulDivUp(a1, b, d) <= ghostMulDivUp(a2, b, d), "mulDivUp is monotone in the first argument";

    // mulDivUp is at least mulDivDown (proven in MulDiv.spec as mulDivUpGeqMulDivDown).
    require forall mathint a. forall mathint b. forall mathint d. d > 0 => ghostMulDivUp(a, b, d) >= ghostMulDivDown(a, b, d), "mulDivUp is at least mulDivDown";

    // If lltv * lif <= WAD^2 then mulDivUp(a, lltv, WAD) <= mulDivUp(a, WAD, lif).
    require forall mathint a. forall mathint lif. forall mathint lltv. a >= 0 && lltv * lif <= WAD() * WAD() => ghostMulDivUp(a, lltv, WAD()) <= ghostMulDivUp(a, WAD(), lif), "if lltv * lif <= WAD^2 then mulDivUp(a, lltv, WAD) <= mulDivUp(a, WAD, lif)";
    require forall uint256 lltv. forall uint256 cursor. lltv * maxLifGhost(lltv, cursor) <= WAD() * WAD(), "maxLif is at most 1/lltv";

    uint256 badDebtBefore = realizableBadDebt(market, id, borrower);

    f(e, args);

    uint256 badDebtAfter = realizableBadDebt(market, id, borrower);

    assert badDebtAfter <= badDebtBefore;
}

// liquidate drops totalUnits by exactly the realized bad debt.
rule liquidateRealizesTotalUnits(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(market);

    require debt(id, borrower) <= totalUnits(id), "proven by totalUnitsEqualsSumNegativeDebtPlusWithdrawable";

    uint256 badDebtBefore = realizableBadDebt(market, id, borrower);
    uint256 totalUnitsBefore = totalUnits(id);
    assert badDebtBefore <= totalUnitsBefore;

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    assert totalUnits(id) == totalUnitsBefore - badDebtBefore;
}
