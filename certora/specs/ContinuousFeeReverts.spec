// SPDX-License-Identifier: GPL-2.0-or-later

// EQUIVALENCE OF REVERTS: activating the continuous fee never makes `take` revert in new ways.
//
// The continuous-fee *rate* (marketState[id].continuousFee) is read in exactly one function, take, and its
// value propagates to only three places:
//   - Midnight.sol:393-394  buyerPendingFeeIncrease = toUint128(buyerCreditIncrease.mulDivDown(continuousFee * ttm, WAD))
//   - Midnight.sol:416       buyerPos.pendingFee += buyerPendingFeeIncrease
//   - Midnight.sol:458       buyerPendingFeeIncrease is passed to the onBuy callback
// Everything else in take (prices, settlementFee, buyer/seller assets, consumed checks, gates, the seller
// side, _updatePosition, transfers, the final isHealthy check) is byte-identical between a run with the rate
// at its configured value and a run with the rate forced to 0. Hence the only NEW revert opportunities the
// enabled run has are the toUint128 cast (394) and the += (416); the callback is assumed to succeed.
//
// We prove this relationally: run take twice from the same pre-state, differing only in the market's fee rate.
//
// Determinism requirement (why this is a separate spec): in a two-run rule every rate-independent helper must
// return identical results across both runs, otherwise the prover could manufacture a spurious revert
// difference. So all helpers are summarized by *deterministic* persistent ghosts (same args => same result),
// not NONDET. None of these summaries needs non-linear reasoning; they only need to cancel between the runs.
// The single piece of non-linear reasoning is the mulDivDown argument bound (axiomMulDivDownArgLeDenom,
// proved in MulDiv.spec) together with the assumption fee*ttm <= WAD (from the fee-rate and TTM caps).

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
    function _.isRatified(Midnight.Offer, bytes) external => deterministicSuccess() expect(bytes32);

    // Token transfers: deterministic no-op (void => no havoc); identical across both runs.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// CONSTANTS ///

definition WAD() returns uint256 = 10 ^ 18;

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
    if (d == 0 || mulOverflow(x, y)) {
        revert();
    }
    return require_uint256(summaryMulDivDownGhost(x, y, d));
}

function summaryMulDivUpWithRevert(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (d == 0 || mulOverflow(x, y)) {
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

rule continuousFeeActivationAddsNoReverts(env e, env eSetter, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData) {
    bytes32 id = summaryToId(offer.market);
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    // timeToMaturity exactly as take computes it: zeroFloorSub(maturity, block.timestamp).
    mathint ttm = offer.market.maturity > e.block.timestamp ? offer.market.maturity - e.block.timestamp : 0;

    // fee*ttm <= WAD follows from continuousFee <= MAX_CONTINUOUS_FEE, ttm <= MAX_TTM, and
    // MAX_CONTINUOUS_FEE * MAX_TTM < WAD. With the mulDivDown argument axiom this bounds the buyer fee
    // increase by the credit increase.
    require to_mathint(continuousFee(id)) * ttm <= WAD(), "fee*ttm <= WAD: fee-rate cap + TTM cap, see Midnight.spec";

    // updatePosition preserves pendingFee <= credit (pendingContinuousFeeBoundedByCredit). Because the
    // mulDiv ghosts are deterministic, this view call computes exactly the post-slash/post-accrual buyer
    // credit and pendingFee that take's _updatePosition writes before the fee addition at Midnight.sol:416.
    // Requiring the bound here excludes states where the slash result has pendingFee > credit, which saves
    // reproving that known invariant via extra mulDiv axioms. This is what makes the += at 416 provably
    // non-overflowing in the enabled run whenever the disabled run's credit += creditIncrease at 417 succeeds.
    // If updatePositionView reverts, that path is pruned, but on it take's identical
    // _updatePosition reverts too, so both takes revert and the assert holds trivially.
    uint128 postCreditBuyer;
    uint128 postPendingBuyer;
    postCreditBuyer, postPendingBuyer, _ = updatePositionView(e, offer.market, id, buyer);
    require postPendingBuyer <= postCreditBuyer, "pendingContinuousFeeBoundedByCredit, preserved by updatePosition";

    // Setter preconditions so the disabled pre-state differs from the enabled one only in the fee rate.
    require eSetter.msg.value == 0 && eSetter.msg.sender == currentContract.feeSetter, "valid fee setter call";
    require tickSpacing(id) > 0, "market is created";

    storage initState = lastStorage;

    // Enabled run: take with the arbitrary configured rate.
    take@withrevert(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);
    bool revertedEnabled = lastReverted;

    // Disabled pre-state: restore initState and force the rate to 0 via the real setter (writes only
    // continuousFee), so the only delta versus initState is the rate. Then run the same take.
    setMarketContinuousFee(eSetter, id, 0) at initState;
    take@withrevert(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);
    bool revertedDisabled = lastReverted;

    assert !revertedDisabled => !revertedEnabled, "activating the continuous fee must not add reverts to take";
}
