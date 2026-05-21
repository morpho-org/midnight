// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic toId needed to link market arguments to stored state.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // SafeTransferLib summaries: bypass transfer logic (needed for liquidate @withrevert rules).
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // External calls are assumed non-reentrant: this is justified as we verify properties about the function's bodies.
    // External calls are assumed non-reverting: we verify that reverts do not happen in the function's bodies.
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// The market's lossFactor is only modified by liquidate.
rule onlyLiquidateChangesMarketLossFactor(bytes32 id, method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
    uint128 lossFactorBefore = currentContract.marketState[id].lossFactor;

    f(e, args);

    assert currentContract.marketState[id].lossFactor == lossFactorBefore;
}

/// In liquidate, the market's lossFactor changes if and only if bad debt is realized (totalUnits decreases).
rule lossFactorChangesIffBadDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool healthyPath) {
    bytes32 id = summaryToId(market);
    uint128 lossFactorBefore = currentContract.marketState[id].lossFactor;
    uint256 totalUnitsBefore = totalUnits(id);

    require lossFactorBefore < max_uint128, "market lossFactor must not be saturated";

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, healthyPath, receiver, callback, data);

    bool lossFactorChanged = currentContract.marketState[id].lossFactor != lossFactorBefore;
    bool badDebtOccurred = totalUnits(id) < totalUnitsBefore;

    assert lossFactorChanged <=> badDebtOccurred;
}

/// After updatePosition, the user's lastLossFactor is synced to the market's lossFactor.
rule updatePositionSyncsLastLossFactor(env e, Midnight.Market market, address user) {
    bytes32 id = summaryToId(market);

    updatePosition(e, market, user);

    assert lastLossFactor(id, user) == currentContract.marketState[id].lossFactor;
}

/// Assuming that the market is created, the loss factor computation in updatePosition does not revert.
rule updatePositionDoesNotRevert(env e, Midnight.Market market, address user) {
    bytes32 id = summaryToId(market);

    require marketIsCreated(market), "market must be created";
    require lastLossFactor(id, user) <= currentContract.marketState[id].lossFactor, "lastLossFactor bounded by market lossFactor, already proved in Midnight.spec";
    require pendingFee(id, user) <= creditOf(id, user), "pending fee bounded by credit, already proved in Midnight.spec";
    require currentContract.position[id][user].lastAccrual <= e.block.timestamp, "lastAccrual <= block.timestamp by timestamp monotonicity";
    require e.block.timestamp < 2 ^ 128, "reasonable timestamp";
    require currentContract.marketState[id].continuousFeeCredit + pendingFee(id, user) <= max_uint128, "Total credit should be bounded by 2^128 and an increase of continuous fee credit should corresponds to a similar decrease of credit";

    require e.msg.value == 0, "setup the call";
    updatePosition@withrevert(e, market, user);

    assert !lastReverted, "updatePosition should not revert under valid state";
}

/// The loss factor arithmetic in liquidate does not revert under valid state. Uses seizedAssets=0, repaidUnits=0 to isolate the bad debt realization path. Uses collateralBitmap=0 to skip the collateral loop, ensuring badDebt == position.debt.
rule liquidateLossFactorDoesNotRevert(env e, Midnight.Market market, address borrower, bytes data) {
    bytes32 id = summaryToId(market);

    require data.length == 0, "no callback to avoid unrelated external call reverts";
    require marketIsCreated(market), "market must be created";
    require market.liquidatorGate == 0, "Assumption:no liquidator gate";
    require market.collateralParams.length > 0, "market has at least one collateral (enforced by touchMarket)";
    require !liquidationLocked(id, borrower), "liquidation not locked (transient storage is zero at transaction start)";
    require currentContract.position[id][borrower].collateralBitmap == 0, "Assumption: no active collaterals: skip loop and maximize badDebt";
    require currentContract.position[id][borrower].debt > 0, "borrower must have debt to enter badDebt > 0 block";
    require currentContract.position[id][borrower].debt <= currentContract.marketState[id].totalUnits, "position debt bounded by totalUnits (see totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";
    require e.msg.value == 0, "Midnight is not payable";

    address zero = 0;
    liquidate@withrevert(e, market, 0, 0, 0, borrower, false, borrower, zero, data);

    assert !lastReverted, "liquidate should not revert under valid state (bad debt realization path)";
}
