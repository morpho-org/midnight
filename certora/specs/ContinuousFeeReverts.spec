// SPDX-License-Identifier: GPL-2.0-or-later

// EQUIVALENCE OF REVERTS: activating the continuous fee never makes `take` revert in new ways, provided 
// the fee doesn't exceed the offer's continuousFeeCap.

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Deterministic id: links the market argument to stored state, identical across both runs.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;

    // Deterministic ghost summaries of the rate-independent helpers (see header).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDownWithRevert(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUpWithRevert(x, y, d);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => ghostTickToPrice(tick);
    function settlementFee(bytes32 id, uint256 ttm) internal returns (uint256) => ghostSettlementFee(id, ttm);
    function isHealthy(Midnight.Market memory market, bytes32 id, address user) internal returns (bool) => ghostIsHealthy(id, user);
    function UtilsLib.tExchange(uint256 slot, bytes32 id, address user, bool val) internal returns (bool) => ghostTExchange(slot, id, user, val);
    function UtilsLib.tGet(uint256 slot, bytes32 id, address user) internal returns (bool) => ghostTGet(slot, id, user);

    // Enter/liquidator gates: deterministic per (gate, user) so the rate-independent gate decision is
    // identical across both runs. Without this they get an AUTO summary that havocs (and can revert)
    // independently per run, producing a spurious revert difference.
    function _.canIncreaseCredit(address user) external => ghostCanIncreaseCredit(calledContract, user) expect(bool);
    function _.canIncreaseDebt(address user) external => ghostCanIncreaseDebt(calledContract, user) expect(bool);
    function _.canLiquidate(address user) external => ghostCanLiquidate(calledContract, user) expect(bool);

    // Callbacks and ratifier: assumed to succeed deterministically. We verify take's own body, not the
    // behavior of untrusted callbacks, and this spec (like ContinuousFee.spec) assumes no reentrancy.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => deterministicSuccess() expect(bytes32);
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => deterministicSuccess() expect(bytes32);
    function _.isRatified(Midnight.Offer, bytes, address) external => deterministicSuccess() expect(bytes32);

    // Token transfers: deterministic no-op (void => no havoc); identical across both runs.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// CONSTANTS ///

definition WAD() returns uint256 = 10 ^ 18;

definition MAX_TTM() returns mathint = 100 * 365 * 86400;

/// DETERMINISTIC GHOST SUMMARIES ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

// mulDivDown: deterministic, reverts on d == 0 and on x*y overflow (see mulOverflow below). 
// The axiom mulDivArgumentLesserThanDenominator, proved in MulDiv.spec, is needed:
//     y <= d => result <= x.
// This bounds the enabled-run fee increase by buyerCreditIncrease.
// Every other mulDivDown call is rate-independent and cancels between the two runs, so it
// needs no axiom (the ghost being deterministic suffices).
persistent ghost summaryMulDivDownGhost(mathint, mathint, mathint) returns mathint {
    axiom forall mathint x. forall mathint y. forall mathint d. (d > 0 && 0 <= y && y <= d) => summaryMulDivDownGhost(x, y, d) <= x;
}

// mulDivUp: deterministic, reverts on d == 0 and on x*y overflow. It needs NO value axioms: every mulDivUp
// call is either rate-independent (so it cancels between the runs) or inside updatePositionView (where a
// revert just prunes the path, since we require its post-update bound directly rather than proving it).
persistent ghost summaryMulDivUpGhost(mathint, mathint, mathint) returns mathint;

// mulDiv reverts when x*y overflows 256 bits. We model that overflow as a deterministic uninterpreted
// predicate rather than the literal nonlinear `x * y >= 2^256`, for two reasons:
//   - The many rate-independent mulDiv calls have identical (x,y) across both runs, so they share the same
//     overflow outcome by congruence (an uninterpreted function), with no nonlinear arithmetic to discharge.
//   - The one rate-dependent fee mulDiv (x = buyerCreditIncrease, y = continuousFee*ttm) is provably
//     non-overflowing via the LINEAR safe-region axiom below instead of a product-of-bounds NIA argument.
// Soundness: the axiom only asserts no-overflow where it genuinely holds (x,y <= max_uint128 => x*y < 2^256),
// so it never hides a real overflow revert. Outside that region the predicate is free, but in every such case
// both runs revert anyway (e.g. the rate-independent toUint128(buyerCreditIncrease) at Midnight.sol:417).
persistent ghost mulOverflow(mathint, mathint) returns bool {
    axiom forall mathint x. forall mathint y. (0 <= x && x <= max_uint128 && 0 <= y && y <= max_uint128) => !mulOverflow(x, y);
}

function summaryMulDivDownWithRevert(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0 || x * y >= 2^256) {
        revert();
    }
    return require_uint256(summaryMulDivDownGhost(x, y, d));
}

function summaryMulDivUpWithRevert(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0 || x * y + d - 1 >= 2^256) {
        revert();
    }
    return require_uint256(summaryMulDivUpGhost(x, y, d));
}

persistent ghost ghostCanIncreaseCredit(address, address) returns bool;

persistent ghost ghostCanIncreaseDebt(address, address) returns bool;

persistent ghost ghostCanLiquidate(address, address) returns bool;

persistent ghost ghostTickToPrice(uint256) returns uint256;

persistent ghost ghostSettlementFee(bytes32, uint256) returns uint256;

persistent ghost ghostIsHealthy(bytes32, address) returns bool;

persistent ghost ghostTExchange(uint256, bytes32, address, bool) returns bool;

persistent ghost ghostTGet(uint256, bytes32, address) returns bool;

function deterministicSuccess() returns bytes32 {
    return Utils.callbackSuccess();
}

/// RULE ///

// Activating the continuous fee never makes `take` revert in new ways, provided the fee doesn't
// exceed the offer's continuousFeeCap.
//
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

    assert !revertedDisabled => !revertedEnabled, "activating the continuous fee must not add reverts to take";
}
