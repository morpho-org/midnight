// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function _.price() external => NONDET;

    // Deterministic toId needed to link obligation arguments to stored state.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Callbacks and external calls assumed non-reentrant.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
}

/// HELPERS ///

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

/// LOSS INDEX IS ONLY CHANGED WHEN BAD DEBT HAPPENS ///

/// The obligation's lossIndex is only modified by `liquidate`.
rule onlyLiquidateChangesObligationLossIndex(bytes32 id, method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector } {
    uint128 lossIndexBefore = currentContract.obligationState[id].lossIndex;

    f(e, args);

    assert currentContract.obligationState[id].lossIndex == lossIndexBefore;
}

/// In `liquidate`, the obligation's lossIndex changes if and only if bad debt is realized (totalUnits decreases).
rule lossIndexChangesIffBadDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = summaryToId(obligation);
    uint128 lossIndexBefore = currentContract.obligationState[id].lossIndex;
    uint256 totalUnitsBefore = totalUnits(id);

    require lossIndexBefore < max_uint128, "obligation lossIndex must not be saturated";

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    bool lossIndexChanged = currentContract.obligationState[id].lossIndex != lossIndexBefore;
    bool badDebtOccurred = totalUnits(id) < totalUnitsBefore;

    assert lossIndexChanged <=> badDebtOccurred;
}

/// LOSS INDEX: UPDATE POSITION EFFECTS ///

/// `updatePosition` can only decrease the user's credit through slashing and fee accrual.
rule updatePositionDecreasesCredit(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = summaryToId(obligation);

    require obligationCreated(id), "obligation must be created";
    require userLossIndex(id, user) <= currentContract.obligationState[id].lossIndex, "user lossIndex bounded by obligation lossIndex, already proved in Midnight.spec";
    require pendingFee(id, user) <= creditOf(id, user), "pending fee bounded by credit, already proved in Midnight.spec";
    require to_mathint(e.block.timestamp) < 2 ^ 128, "reasonable timestamp";

    uint256 creditBefore = creditOf(id, user);

    updatePosition(e, obligation, user);

    assert creditOf(id, user) <= creditBefore;
}

/// After `updatePosition`, the user's lossIndex is synced to the obligation's lossIndex.
rule updatePositionSyncsLossIndex(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = summaryToId(obligation);

    updatePosition(e, obligation, user);

    assert userLossIndex(id, user) == currentContract.obligationState[id].lossIndex;
}
