// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function userLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function _.price() external => NONDET;

    // Deterministic toId needed to link obligation arguments to stored state.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    // Required: without these, PTA fails on Midnight.take() and cascades into storage-splitting failure for the whole Midnight contract, breaking storage-path compilation for every rule below (even those that never call take).
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;

    // SafeTransferLib summaries: bypass transfer logic (needed for liquidate @withrevert rules).
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // External calls are assumed non-reentrant.
}

/// HELPERS ///

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

/// The obligation's lossFactor is only modified by `liquidate`.
rule onlyLiquidateChangesObligationLossFactor(bytes32 id, method f, env e, calldataarg args) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, address, address, bytes).selector } {
    uint128 lossFactorBefore = currentContract.obligationState[id].lossFactor;

    f(e, args);

    assert currentContract.obligationState[id].lossFactor == lossFactorBefore;
}

/// In `liquidate`, the obligation's lossFactor changes if and only if bad debt is realized (totalUnits decreases).
rule lossFactorChangesIffBadDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    bytes32 id = summaryToId(obligation);
    uint128 lossFactorBefore = currentContract.obligationState[id].lossFactor;
    uint256 totalUnitsBefore = totalUnits(id);

    require lossFactorBefore < max_uint128, "obligation lossFactor must not be saturated";

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    bool lossFactorChanged = currentContract.obligationState[id].lossFactor != lossFactorBefore;
    bool badDebtOccurred = totalUnits(id) < totalUnitsBefore;

    assert lossFactorChanged <=> badDebtOccurred;
}

/// After `updatePosition`, the user's lossFactor is synced to the obligation's lossFactor.
rule updatePositionSyncsLossFactor(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = summaryToId(obligation);

    updatePosition(e, obligation, user);

    assert userLossFactor(id, user) == currentContract.obligationState[id].lossFactor;
}

/// Under valid state, the loss factor slash computation in `updatePosition` does not revert.
rule updatePositionDoesNotRevert(env e, Midnight.Obligation obligation, address user) {
    bytes32 id = summaryToId(obligation);

    require obligationCreated(id), "obligation must be created";
    require userLossFactor(id, user) <= currentContract.obligationState[id].lossFactor, "user lossFactor bounded by obligation lossFactor, already proved in Midnight.spec";
    require pendingFee(id, user) <= creditOf(id, user), "pending fee bounded by credit, already proved in Midnight.spec";
    require currentContract.position[id][user].lastAccrual <= e.block.timestamp, "lastAccrual <= block.timestamp by timestamp monotonicity";
    require to_mathint(e.block.timestamp) < 2 ^ 128, "reasonable timestamp";
    require to_mathint(currentContract.obligationState[id].continuousFeeCredit) + to_mathint(pendingFee(id, user)) <= to_mathint(max_uint128), "continuousFeeCredit + accruable fee does not overflow (accruedFee <= pendingFee)";
    require e.msg.value == 0, "Midnight is not payable";

    updatePosition@withrevert(e, obligation, user);

    assert !lastReverted, "updatePosition should not revert under valid state";
}

/// The loss factor arithmetic in `liquidate` does not revert under valid state.
/// Uses seizedAssets=0, repaidUnits=0 to isolate the bad debt realization path.
/// Uses collateralBitmap=0 to skip the collateral loop, ensuring badDebt == position.debt.
rule liquidateLossFactorDoesNotRevert(env e, Midnight.Obligation obligation, address borrower, bytes data) {
    bytes32 id = summaryToId(obligation);

    require data.length == 0, "no callback to avoid unrelated external call reverts";
    require obligationCreated(id), "obligation must be created";
    require obligation.liquidatorGate == 0, "Assumption:no liquidator gate";
    require obligation.collateralParams.length > 0, "obligation has at least one collateral (enforced by touchObligation)";
    require !liquidationLocked(id, borrower), "liquidation not locked (transient storage is zero at transaction start)";
    require currentContract.position[id][borrower].collateralBitmap == 0, "Assumption: no active collaterals: skip loop and maximize badDebt";
    require currentContract.position[id][borrower].debt > 0, "borrower must have debt to enter badDebt > 0 block";
    require currentContract.position[id][borrower].debt <= currentContract.obligationState[id].totalUnits, "position debt bounded by totalUnits (see totalUnitsEqualsSumNegativeDebtPlusWithdrawable)";
    require e.msg.value == 0, "Midnight is not payable";

    address zero = 0;
    liquidate@withrevert(e, obligation, 0, 0, 0, borrower, borrower, zero, data);

    assert !lastReverted, "liquidate should not revert under valid state (bad debt realization path)";
}
