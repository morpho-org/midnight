// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    // Oracle: deterministic per oracle address so isHealthy() and liquidate()'s loop see the same prices.
    function _.price() external => oraclePrice(calledContract) expect(uint256);

    // Deterministic toId so the obligation argument links to stored state.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    // PTA workaround for take().
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    // Transfers: assumed well-behaved (no revert) — focus is on the protocol's own logic.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

/// HELPERS ///

definition WAD() returns uint256 = 10 ^ 18;

// Oracle prices are bounded by max_uint128, matching the uint128 collateral amounts.
persistent ghost oraclePrice(address) returns uint256 {
    axiom forall address oracle. oraclePrice(oracle) <= max_uint128;
}

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

/// Debts can always be liquidated if expired
rule liquidateExpiredDoesNotRevert(env e, Midnight.Obligation obligation, address borrower, bytes data) {
    bytes32 id = summaryToId(obligation);

    require data.length == 0, "no callback data";
    require obligationCreated(id), "obligation must be created";
    require obligation.liquidatorGate == 0, "no liquidator gate";
    require obligation.collateralParams.length > 0, "obligation has at least one collateral (touchObligation invariant)";
    require obligation.collateralParams.length <= 10, "loop bound to keep verification tractable";
    require !liquidationLocked(id, borrower), "liquidation not locked at transaction start";
    require currentContract.position[id][borrower].debt > 0, "borrower has debt to enter the bad-debt branch";
    require currentContract.position[id][borrower].debt <= currentContract.obligationState[id].totalUnits, "debt bounded by totalUnits (Midnight.spec)";
    require currentContract.obligationState[id].lossFactor < max_uint128, "lossFactor not saturated";
    require currentContract.obligationState[id].totalUnits > 0, "totalUnits > 0 (implied by debt > 0 above)";
    // touchObligation enforces maxLif == maxLif(lltv, cursor); the formula yields a value in [WAD, 2*WAD].
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].maxLif > 0 && obligation.collateralParams[i].maxLif <= 2 * WAD(), "WAD <= maxLif <= 2*WAD (touchObligation invariant)";
    // touchObligation's maxLif formula requires lltv < WAD; lltv = WAD gives maxLif = WAD.
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD(), "lltv <= WAD (touchObligation invariant)";
    // depositCollateral/withdrawCollateral only set/clear bits for valid indices.
    require forall uint256 bit. summaryGetBit(currentContract.position[id][borrower].collateralBitmap, bit) => bit < obligation.collateralParams.length, "bitmap bits within collateralParams bounds";
    require e.msg.value == 0, "Midnight is not payable";
    // Expiration requirement
    require e.block.timestamp > obligation.maturity, "obligation has expired";

    address zero = 0;
    liquidate@withrevert(e, obligation, 0, 0, 0, borrower, borrower, zero, data);

    assert !lastReverted;
}

/// Debts can always be liquidated if unhealthy
rule liquidateUnhealthyDoesNotRevert(env e, Midnight.Obligation obligation, address borrower, bytes data) {
    bytes32 id = summaryToId(obligation);

    require data.length == 0, "no callback data";
    require obligationCreated(id), "obligation must be created";
    require obligation.liquidatorGate == 0, "no liquidator gate";
    require obligation.collateralParams.length > 0, "obligation has at least one collateral (touchObligation invariant)";
    require obligation.collateralParams.length <= 10, "loop bound to keep verification tractable";
    require !liquidationLocked(id, borrower), "liquidation not locked at transaction start";
    require currentContract.position[id][borrower].debt > 0, "borrower has debt to enter the bad-debt branch";
    require currentContract.position[id][borrower].debt <= currentContract.obligationState[id].totalUnits, "debt bounded by totalUnits (Midnight.spec)";
    require currentContract.obligationState[id].lossFactor < max_uint128, "lossFactor not saturated";
    require currentContract.obligationState[id].totalUnits > 0, "totalUnits > 0";
    // touchObligation enforces maxLif == maxLif(lltv, cursor); the formula yields a value in [WAD, 2*WAD].
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].maxLif > 0 && obligation.collateralParams[i].maxLif <= 2 * WAD(), "WAD <= maxLif <= 2*WAD (touchObligation invariant)";
    // touchObligation's maxLif formula requires lltv < WAD; lltv = WAD gives maxLif = WAD.
    require forall uint256 i. i < obligation.collateralParams.length => obligation.collateralParams[i].lltv <= WAD(), "lltv <= WAD (touchObligation invariant)";
    // depositCollateral/withdrawCollateral only set/clear bits for valid indices.
    require forall uint256 bit. summaryGetBit(currentContract.position[id][borrower].collateralBitmap, bit) => bit < obligation.collateralParams.length, "bitmap bits within collateralParams bounds";
    require e.msg.value == 0, "Midnight is not payable";
    // Unhealthy requirement
    require !isHealthy(obligation, id, borrower), "borrower is unhealthy (debt > maxDebt under shared mulDiv/oracle ghosts)";

    address zero = 0;
    liquidate@withrevert(e, obligation, 0, 0, 0, borrower, borrower, zero, data);

    assert !lastReverted;
}
