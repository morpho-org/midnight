// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

import "UpdatedCredit.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic toId summary.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // This spec needs the HAVOC_ECF semantics for all callbacks (take/liquidate/flashLoan) to prevent the callbacks from violating the property.
    // The code is still reentrancy safe as the callbacks can only call public functions and for these we check the properties here.
    // However, this cannot be checked with the Certora Prover and it would also require a more complicated spec, e.g., flashLoan can change withdrawable amount if the callback withdraws.
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

/// RULES ///

/// Only `withdraw` and `claimContinuousFee` can ever decrease the market's withdrawable pool; every other function leaves it unchanged or increases it.
rule withdrawableOnlyDecreasesOnWithdrawOrClaimContinuousFee(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector } {
    uint256 withdrawableBefore = withdrawable(id);

    f(e, args);

    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter >= withdrawableBefore;
}

/// A withdrawal can only take out what the withdrawing position is actually owed: the resulting decrease in the market's withdrawable pool is bounded by the position's credit before the call.
rule withdrawDecreaseBoundedByCredit(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    bytes32 id = summaryToId(market);
    bytes32 otherid;
    uint256 creditBefore = updatedCredit(e, market, id, onBehalf);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 withdrawableOtherBefore = withdrawable(otherid);

    withdraw(e, market, units, onBehalf, receiver);

    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableBefore - withdrawableAfter <= creditBefore;
    assert withdrawableAfter <= withdrawableBefore;

    // check that other markets are not affected at all.
    uint256 withdrawableOtherAfter = withdrawable(otherid);
    assert id != otherid => withdrawableOtherAfter == withdrawableOtherBefore;
}

/// claimContinuousFee decreases withdrawable by at most the credited fee.
rule claimContinuousFeeDecreaseBoundedByCredit(env e, Midnight.Market market, uint256 amount, address receiver) {
    bytes32 id = summaryToId(market);
    bytes32 otherid;
    uint256 continuousFeeCreditBefore = continuousFeeCredit(id);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 withdrawableOtherBefore = withdrawable(otherid);

    claimContinuousFee(e, market, amount, receiver);

    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableBefore - withdrawableAfter <= continuousFeeCreditBefore;
    assert withdrawableAfter <= withdrawableBefore;

    // check that other markets are not affected at all.
    uint256 withdrawableOtherAfter = withdrawable(otherid);
    assert id != otherid => withdrawableOtherAfter == withdrawableOtherBefore;
}

/// Post maturity, a market's totalUnits can never increase.
rule totalUnitsCannotIncreasePostMaturity(env e, method f, calldataarg args, Midnight.Market market) filtered { f -> !f.isView } {
    bytes32 id = summaryToId(market);

    mathint totalUnitsBefore = totalUnits(id);

    f(e, args);

    assert e.block.timestamp > market.maturity => totalUnits(id) <= totalUnitsBefore;
}
