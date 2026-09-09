// SPDX-License-Identifier: GPL-2.0-or-later

// EQUIVALENCE OF REVERTS: activating the continuous fee never makes `take` revert in new ways, provided the fee doesn't exceed the offer's continuousFeeCap.
// Assumptions:
// * Price oracles don't revert and return the same price for both `take` calls.
// * Gates are deterministic and don't revert (they can return false, but then they do it in both calls).
// * Callbacks and ratifier succeed.
// * No reverts caused by tickToPrice or settlementFee.
// * Token transfers don't revert or change the state of the contract. 

import "BitmapSummaries.spec";
import "MulDivAxioms.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Deterministic id: links the market argument to stored state, identical across both runs.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Deterministic ghost summaries of the internal math functions.
    // Reverts in mulDivDown/Up are overapproximated by a deterministic overflow function.
    // We ignore reverts in tickToPrice (it would revert for both `take` calls equally).
    // We assume that settlementFee never reverts for created markets (proved in settlementFeeSpreadBounds in SettlementFeeSpread.spec).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDownWithRevert(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUpWithRevert(x, y, d);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => ghostTickToPrice(tick);
    function settlementFee(bytes32 id, uint256 ttm) internal returns (uint256) => ghostSettlementFee(id, ttm);

    // Enter gates: deterministic per (gate, user) so the rate-independent gate decision is identical across both runs.
    // Assumes no reverts, but they can return false, so the revert case is indirectly tested.
    function _.canIncreaseCredit(address user) external => ghostCanIncreaseCredit(calledContract, user) expect(bool);
    function _.canIncreaseDebt(address user) external => ghostCanIncreaseDebt(calledContract, user) expect(bool);

    // Oracle summary: we assume the price does not change between the two calls to take and never reverts.
    function _.price() external => PER_CALLEE_CONSTANT;

    // Callbacks and ratifier: assumed to succeed deterministically. We verify take's own body, not the behavior of untrusted callbacks, and this spec (like ContinuousFee.spec) assumes no reentrancy.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => deterministicSuccess() expect(bytes32);
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => deterministicSuccess() expect(bytes32);
    function _.isRatified(Midnight.Offer, bytes, address) external => deterministicSuccess() expect(bytes32);

    // Token transfers: deterministic no-op (void => no havoc); assumes they never revert and have no side-effects visible to this spec.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

/// CONSTANTS ///

definition MAX_TTM() returns mathint = 100 * 365 * 86400;

/// DETERMINISTIC GHOST SUMMARIES ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

persistent ghost ghostMulDivDownOverflow(uint256, uint256, uint256) returns bool {
    // No overflow if both a and b fit in uint128, because overflow condition is a * b >= 2^256.
    axiom forall uint256 a. forall uint256 b. forall uint256 d. a < 2 ^ 128 && b < 2 ^ 128 => !ghostMulDivDownOverflow(a, b, d);
}

persistent ghost ghostMulDivUpOverflow(uint256, uint256, uint256) returns bool;

function summaryMulDivDownWithRevert(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0 || ghostMulDivDownOverflow(x, y, d)) {
        revert();
    }
    require axiomMathMulDivDownArgumentLesserThanDenominatorB(x, y, d), "axiom";
    return require_uint256(ghostMulDivDown(x, y, d));
}

function summaryMulDivUpWithRevert(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0 || ghostMulDivUpOverflow(x, y, d)) {
        revert();
    }
    return require_uint256(ghostMulDivUp(x, y, d));
}

persistent ghost ghostCanIncreaseCredit(address, address) returns bool;

persistent ghost ghostCanIncreaseDebt(address, address) returns bool;

persistent ghost ghostTickToPrice(uint256) returns uint256;

persistent ghost ghostSettlementFee(bytes32, uint256) returns uint256;

function deterministicSuccess() returns bytes32 {
    return Utils.callbackSuccess();
}

/// RULE ///

// Activating the continuous fee never makes `take` revert in new ways, provided the fee doesn't exceed the offer's continuousFeeCap.
// We prove this relationally: run take twice from the same pre-state, differing only in the market's fee rate.
rule continuousFeeActivationAddsNoReverts(env e, env eSetter, uint256 newContinuousFee, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    bytes32 id = summaryToId(offer.market);

    // The offer can intentionally reject the continuous fee if it exceeds the cap.
    require newContinuousFee <= offer.continuousFeeCap, "assume offer is compatible with new continuous fee";

    // timeToMaturity exactly as take computes it: zeroFloorSub(maturity, block.timestamp).
    mathint ttm = offer.market.maturity > e.block.timestamp ? offer.market.maturity - e.block.timestamp : 0;
    require ttm <= MAX_TTM(), "maturity less than MAX_TTM() in the future, see Midnight.spec";

    // updatePosition preserves pendingFee <= credit
    // proved as pendingContinuousFeeBoundedByCredit in Midnight.spec.
    address buyer = offer.buy ? offer.maker : taker;
    uint128 postCreditBuyer;
    uint128 postPendingBuyer;
    postCreditBuyer, postPendingBuyer, _ = updatePositionView(e, offer.market, id, buyer);
    require postPendingBuyer <= postCreditBuyer, "pendingContinuousFeeBoundedByCredit, preserved by updatePosition";

    storage initState = lastStorage;

    // arbitrary pre-state before continuous fee is set.  Record its revert status.
    take@withrevert(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);
    bool revertedDisabled = lastReverted;

    // now set the new continuous fee and check again.
    setMarketContinuousFee(eSetter, id, newContinuousFee) at initState;

    // Enabled run: take with the arbitrary configured rate.
    take@withrevert(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);
    bool revertedEnabled = lastReverted;

    assert !revertedDisabled => !revertedEnabled;
}
