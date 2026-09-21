// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
//
// Shows that once a market has matured, nobody can manipulate its withdrawable pool arbitrarily:
// - withdrawableOnlyDecreasesOnWithdrawOrClaimContinuousFee shows that only `withdraw` and
//   `claimContinuousFee` can ever decrease the withdrawable pool; every other function leaves it
//   unchanged or increases it.
// - withdrawDecreaseBoundedByCredit bounds every single withdrawal by the withdrawer's own credit.
// - totalUnitsCannotIncreasePostMaturity shows that the pool everything is paid out of, totalUnits
//   (== sum of all recorded debt + withdrawable, see totalUnitsEqualsSumNegativeDebtPlusWithdrawable
//   in Midnight.spec), can only shrink post maturity.
// Together, post maturity a user can only ever withdraw at most what they are owed, out of a pool
// that itself never grows back.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function credit(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic toId summary.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // This spec needs the HAVOC_ECF semantics for all callbacks (take/liquidate/flashLoan) to prevent the
    // callbacks from violating the property.
    // The code is still reentrancy safe as the callbacks can only call a public function and for these we
    // check the properties here.  However, this cannot be checked with the Certora Prover.
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

/// RULES ///

/// Only `withdraw` and `claimContinuousFee` can ever decrease the market's withdrawable pool;
/// every other function leaves it unchanged or increases it.
rule withdrawableOnlyDecreasesOnWithdrawOrClaimContinuousFee(env e, method f, calldataarg args, bytes32 id) filtered { f -> !f.isView && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector } {
    uint256 withdrawableBefore = withdrawable(id);

    f(e, args);

    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter >= withdrawableBefore;
}

/// A withdrawal can only take out what the withdrawing position is actually owed: the resulting
/// decrease in the market's withdrawable pool is bounded by the position's credit before the call.
rule withdrawDecreaseBoundedByCredit(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver) {
    bytes32 id = summaryToId(market);
    uint256 creditBefore = credit(id, onBehalf);
    uint256 withdrawableBefore = withdrawable(id);

    withdraw(e, market, units, onBehalf, receiver);

    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableBefore - withdrawableAfter <= creditBefore;
}

/// Post maturity, a market's totalUnits can never increase. `withdraw`, `claimContinuousFee` and bad-debt
/// realization in `liquidate` only ever decrease it, and `take` can only move credit from a seller to a
/// buyer without creating new debt once matured (see the CannotIncreaseDebtPostMaturity require in
/// Midnight.sol), so it cannot increase it either.
rule totalUnitsCannotIncreasePostMaturity(env e, method f, calldataarg args, Midnight.Market market) filtered { f -> !f.isView } {
    bytes32 id = summaryToId(market);

    mathint totalUnitsBefore = totalUnits(id);

    f(e, args);

    assert e.block.timestamp > market.maturity => totalUnits(id) <= totalUnitsBefore;
}
