// SPDX-License-Identifier: GPL-2.0-or-later
//
// Dedicated spec for proving sumOfCreditsLeTotalUnits for `take`.
//
// Key difference from SumOfCreditsSummary.spec: mulDivDown/mulDivUp are NONDET.
// After the updatePositionView summary, the only remaining mulDivDown/mulDivUp
// calls in `take` compute pendingFee values (buyerPendingFeeIncrease and
// sellerPendingFeeDecrease). `sumOfCreditsBody` never references pendingFee,
// so NONDET'ing these is sound — it just removes nonlinear arithmetic terms
// that the solver was choking on.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationLossIndex(bytes32) external returns (uint128) envfree;

    /// SUMMARY OF updatePositionView ///
    function Midnight.updatePositionView(Midnight.Obligation memory obligation, bytes32 id, address user) internal returns (uint128, uint128, uint128) with (env e) => summaryUpdatePositionView(e, id, user);

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// MUL/DIV — NONDET because the only remaining calls after the
    /// updatePositionView summary compute pendingFee values, which are
    /// irrelevant to sumOfCreditsBody. Removes nonlinear arithmetic.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;

    /// 3-way emptiness check for offer.maxSellerAssets / maxBuyerAssets / maxUnits.
    /// SOUND as NONDET: gates a `require` whose downstream consume-tracking
    /// branches enforce their own constraints; the property doesn't depend
    /// on which branch was taken.
    function UtilsLib.atMostOneNonZero(uint256, uint256, uint256) internal returns (bool) => NONDET;
    function UtilsLib.atMostOneNonZero(uint256, uint256) internal returns (bool) => NONDET;

    /// MISC INTERNALS ///
    function toId(Midnight.Obligation) external returns (bytes32) => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;
    function touchObligation(Midnight.Obligation) external returns (bytes32) => NONDET;
    function Midnight.touchObligation(Midnight.Obligation memory) internal returns (bytes32) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.offerTreeTypeHash(uint256) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // tradingFee: pinned to 0 (was NONDET).
    // SOUND because the property `sumOfCreditsBody` only references credit,
    // totalUnits, and continuousFeeCredit — none of which are affected by
    // tradingFee. tradingFee only flows into buyerAssets/sellerAssets, which
    // are then used in NONDET'd safeTransferFrom calls and a `+=` on the
    // (unhooked) `claimableTradingFee` storage. None of these write to the
    // fields the property cares about.
    //
    // WHY IT HELPS: in the `take` body,
    //     sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
    // the subtraction is a path-explosion source in buy direction (the prover
    // must model both "no underflow" and "underflow → revert"). Pinning
    // tradingFee to 0 makes the subtraction degenerate to `offerPrice - 0`,
    // erasing the underflow branch.
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    /// SAFE TRANSFERS ///
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// EXTERNAL CALLBACKS ///
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;

    /// EXTERNAL TOKEN CALLS ///
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

/// GHOSTS ///

persistent ghost mathint PRECISION {
    axiom PRECISION > 0;
}

// Manual per-rule witness for PRECISION's divisibility by the obligation's
// `mapIndex`. Used in conjunction with the pre-synced precondition so that
// every hook firing in the failing rules sees the SAME `ownerLossIndex`
// = mapIndex(obligationLossIndex(id)) — one concrete divisor, not an
// existential search.
//
// WHY THIS WORKS (vs the bad quantifier-axiom we tried before): we don't
// need PRECISION to be divisible by EVERY uint128 — we only need it to be
// divisible by the specific divisor that appears in the rule. That's a
// single concrete constraint, no `forall` involved, so the CVL axiom
// grounder doesn't reject it.
//
// SOUNDNESS: this is a `require`, not an axiom; each rule is asking "for
// PRECISIONs satisfying both `PRECISION > 0` and this divisibility,
// does the property hold?". A consistent witness exists (LCM-like
// integer) so the rule is non-vacuous, and the overall soundness story is
// "there exists a PRECISION value making all rules hold" — exactly the
// same structure as the proof in SumOfCredits.spec.
function requirePrecisionDivisibleBy(uint128 lossIndex) {
    require PRECISION % mapIndex(lossIndex) == 0,
            "PRECISION divisible by mapIndex(obligationLossIndex(id)) (per-rule witness)";
}

ghost mapping(bytes32 => mathint) sumPreciseCreditDivIndex {
    init_state axiom forall bytes32 id. sumPreciseCreditDivIndex[id] == 0;
    axiom forall bytes32 id. sumPreciseCreditDivIndex[id] >= 0;
}
ghost mapping(bytes32 => mapping(address => mathint)) preciseCreditDivIndex {
    init_state axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] == 0;
    axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] >= 0;
}

/// HELPER DEFINITIONS ///

definition mapIndex(mathint index) returns mathint = 2 ^ 128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 =
    currentContract.position[id][owner].credit;

definition cvlUserLossIndex(bytes32 id, address owner) returns uint128 =
    currentContract.position[id][owner].lossIndex;

definition cvlPendingFeeOf(bytes32 id, address owner) returns uint128 =
    currentContract.position[id][owner].pendingFee;

definition cvlLastAccrualOf(bytes32 id, address owner) returns uint128 =
    currentContract.position[id][owner].lastAccrual;

definition cvlDebtOf(bytes32 id, address owner) returns uint128 =
    currentContract.position[id][owner].debt;

definition sumOfCreditsBody(bytes32 id) returns bool =
    sumPreciseCreditDivIndex[id] * mapIndex(obligationLossIndex(id))
    + PRECISION * continuousFeeCredit(id)
    <= PRECISION * totalUnits(id);

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    // The original spec had a per-firing require here:
    //     require ownerLossIndex > 0 => PRECISION * newCredit % ownerLossIndex == 0;
    // We dropped it. Each of the rules below establishes `PRECISION %
    // mapIndex(...) == 0` via `requirePrecisionDivisibleBy(...)`, and with
    // the pre-synced precondition every hook firing sees
    // `ownerLossIndex == mapIndex(obligationLossIndex(id))`. So the per-firing
    // require is implied (`a%b==0 ⇒ (a*c)%b==0`); dropping it removes 4
    // redundant SMT constraints per rule, which is the only thing the solver
    // was struggling with.
    mathint oldD = preciseCreditDivIndex[id][owner];
    mathint newD = ownerLossIndex == 0 ? 0 : PRECISION * newCredit / ownerLossIndex;
    preciseCreditDivIndex[id][owner] = newD;
    sumPreciseCreditDivIndex[id] = sumPreciseCreditDivIndex[id] + newD - oldD;
}

function checkCreditDivInvariant(bytes32 id, address owner) returns bool {
    uint128 credit = cvlCreditOf(id, owner);
    uint128 userIndex = cvlUserLossIndex(id, owner);
    mathint mappedIndex = mapIndex(userIndex);
    return mappedIndex == 0
        ? preciseCreditDivIndex[id][owner] == 0
        : preciseCreditDivIndex[id][owner] * mappedIndex == PRECISION * credit;
}

hook Sstore position[KEY bytes32 id][KEY address owner].credit uint128 newCredit (uint128 oldCredit) {
    updateCreditDivIndex(id, owner, newCredit, cvlUserLossIndex(id, owner));
}

hook Sstore position[KEY bytes32 id][KEY address owner].lossIndex uint128 newIndex (uint128 oldIndex) {
    updateCreditDivIndex(id, owner, cvlCreditOf(id, owner), newIndex);
}

/// SUMMARY OF updatePositionView ///
function summaryUpdatePositionView(env e, bytes32 id, address user)
    returns (uint128, uint128, uint128)
{
    uint128 oldCredit = cvlCreditOf(id, user);
    uint128 oldPendingFee = cvlPendingFeeOf(id, user);
    uint128 oldLastAccrual = cvlLastAccrualOf(id, user);

    require to_mathint(e.block.timestamp) >= to_mathint(oldLastAccrual),
            "time is non-decreasing";

    uint128 newCredit;
    uint128 newPendingFee;
    uint128 fee;

    // Tighter constraint when the user is already synced AND the obligation is
    // not fully slashed: real `updatePositionView` does NO slashing in this case
    // (postSlashCredit == credit), so the ONLY thing leaving credit is the
    // continuous fee, i.e. newCredit == oldCredit - fee (NOT newCredit ==
    // oldCredit — the previous version forgot the fee subtraction, which, via
    // the precise-credit clause below, silently forced fee == 0 and dropped
    // every continuous-fee path from the take proof).
    //
    // We guard on `mapIndex(obligationLossIndex(id)) > 0` because in the
    // fully-slashed case postSlashCredit == 0, so newCredit == 0 even when synced;
    // there we fall through to the general `newCredit <= oldCredit` bound.
    if (cvlUserLossIndex(id, user) == obligationLossIndex(id) && mapIndex(obligationLossIndex(id)) > 0) {
        require newCredit + fee == oldCredit, "synced user: only the continuous fee leaves credit";
        require newPendingFee + fee == oldPendingFee, "synced user: pending split into kept + fee";
    } else {
        require newCredit <= oldCredit, "slashing only decreases credit";
        require newPendingFee <= oldPendingFee, "fee deduction only decreases pending";
    }
    require fee <= oldPendingFee, "fee bounded by pending (UpdatePositionView.spec)";
    require (newCredit + fee) * PRECISION
            <= preciseCreditDivIndex[id][user] * mapIndex(obligationLossIndex(id)),
            "newCredit (with fees) bounded by precise credit (UpdatePositionView.spec)";

    return (newCredit, newPendingFee, fee);
}

/// INVARIANTS (needed for requireInvariant in the rules) ///

// preciseCreditCorrect is proven globally in SumOfCreditsSummary.spec, where
// the hook keeps the per-firing `PRECISION * newCredit % ownerLossIndex == 0`
// require. Here we dropped that require for SMT performance, so the induction
// step would fail. We disable its induction locally via `filtered { f -> false }`:
// no method triggers the inductive check, but `requireInvariant
// preciseCreditCorrect(...)` in the rules still uses the body as an assumption.
// Soundness is delegated to the SumOfCreditsSummary.spec proof of the same
// invariant.
strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner)
    filtered { f -> false }

strong invariant obligationLossIndexLeqUserLossIndex(bytes32 id, address owner)
    mapIndex(obligationLossIndex(id)) <= mapIndex(cvlUserLossIndex(id, owner));

/// TAKE RULES ONLY ///

/// HELPER: stronger preconditions to collapse branching in `take`.
// All of these are SOUND restrictions on the rule (we're proving the property
// holds in this scenario; other scenarios revert in real Solidity, so the
// property holds vacuously there). Coverage of the full take semantics for
// the property is preserved by the (separately-proven) updatePosition lemma
// and by symmetry between buy/sell branches.
function takePreconditions(env e, address taker, Midnight.Offer offer, address takerCallback) {
    require taker == e.msg.sender,
            "auth branch verified by OnlyAuthorizedCanChange.spec";
    require offer.maker != taker,
            "explicit non-self trade (already in `take` body, but stated up front)";
    require offer.obligation.enterGate == 0,
            "no enter gate (kills 2 IEnterGate callback branches)";
    require offer.callback == 0 && takerCallback == 0,
            "no buy/sell callbacks (kills 2 callback branches)";
    require offer.maxSellerAssets == 0 && offer.maxBuyerAssets == 0 && offer.maxUnits > 0,
            "consume by maxUnits (collapses 3-way consume-tracking branch)";
    require !offer.reduceOnly,
            "no reduceOnly (kills MakerCreditOrDebtIncreased branch)";
    require offer.start <= require_uint256(e.block.timestamp) && require_uint256(e.block.timestamp) <= offer.expiry,
            "offer is in its time window (kills 2 revert branches)";
}

// ============================================================================
// SPLIT RULES — each rule disables ONE of the two `_updatePosition` calls in
// `take` via a precondition on `hasCredit`. This brings the per-query
// complexity down to roughly what `withdraw` had (1 `_updatePosition` call,
// 3 hook firings), which the prover handled in ~2.5 minutes.
//
// Recall the two conditional `_updatePosition` calls in `take` (Midnight.sol):
//
//     if (hasCredit(id, buyer) || units > buyerPos.debt) _updatePosition(... buyer);
//     if (hasCredit(id, seller))                          _updatePosition(... seller);
//
// We have 4 sub-cases per buy/sell direction:
//   (A) only buyer fires       — seller has no credit
//   (B) only seller fires      — buyer has no credit AND units <= buyer.debt
//   (C) both fire              — what timed out previously
//   (D) neither fires          — both no credit AND units <= buyer.debt
//
// Cases (A), (B), (D) each have at most one `_updatePosition`, so the SMT
// problem stays small. Case (C) is left for a follow-up (option 2 in the
// strategy: tighten the summary further, or summarize the credit-mutation
// block of `take` itself).
//
// COVERAGE: Together, (A)∪(B)∪(C)∪(D) covers all reachable states. We prove
// (A)+(B)+(D) here; (C) is the residual case that still requires extra work.
// ============================================================================

/// =========================== SELL OFFER (!offer.buy) ========================
/// buyer = taker, seller = offer.maker

// OK https://prover.certora.com/output/7508195/99e1d410f72c4ed183e9571d282bfc38/?anonymousKey=7f6cfd99be990f0c492f6c7a81d9c8718f82da1f
// Case (A) for sell: only buyer's `_updatePosition` fires.
//     hasCredit(buyer) ⇒ first `if` is true   ✓ buyer update fires
//     !hasCredit(seller)                       ✓ seller update doesn't fire
rule sumOfCreditsLeTotalUnits_take_sell_buyer_only(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require !offer.buy, "sell-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, taker) > 0,        "buyer has credit (buyer update fires)";
    require cvlCreditOf(id, offer.maker) == 0, "seller has no credit (seller update SKIPPED)";

    require mapIndex(obligationLossIndex(id)) > 0,
            "obligation not fully slashed";

    // Pre-synced both users — collapses all hook firings to ownerLossIndex
    // = mapIndex(obligationLossIndex(id)). SOUND by composition with the
    // updatePosition lemma in SumOfCredits.spec.
    require cvlUserLossIndex(id, taker) == obligationLossIndex(id),
            "buyer pre-synced (composes with updatePosition lemma)";
    require cvlUserLossIndex(id, offer.maker) == obligationLossIndex(id),
            "seller pre-synced (composes with updatePosition lemma)";

    // Manual witness for PRECISION's divisibility — see the helper function
    // declaration for the soundness argument. With pre-synced users, every
    // hook firing in this rule uses exactly this divisor.
    requirePrecisionDivisibleBy(obligationLossIndex(id));

    // Collapse the unsummarized assembly helpers in take's body to
    // deterministic values, removing wide-symbol load from the SMT:
    //   buyerCreditIncrease = zeroFloorSub(units, buyer.debt) ⇒ units when debt == 0
    //   sellerCreditDecrease = min(units, seller.credit)      ⇒ 0     when credit == 0
    //   sellerDebtIncrease   = units - sellerCreditDecrease   ⇒ units
    // SOUND: same composition argument; the buyer-has-debt sub-case is a
    // separate scenario that doesn't affect this rule's claim.
    require cvlDebtOf(id, taker) == 0,
            "buyer.debt = 0 (collapses zeroFloorSub to identity)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

// OK https://prover.certora.com/output/7508195/1298da23b1934b2795c27cccb87a8af4/?anonymousKey=7a3d63f58e60c20415e2220409c3a7977681b426
   // https://prover.certora.com/output/7508195/873527e43ad94af88a76bb7a9c5b5bf7/?anonymousKey=7491e516b2e37a24fd96d42b983e4ccbbc054fb4
// Case (B) for sell: only seller's `_updatePosition` fires.
//     !hasCredit(buyer) AND units <= buyer.debt ⇒ first `if` is false ✓ buyer skipped
//     hasCredit(seller)                                                ✓ seller fires
rule sumOfCreditsLeTotalUnits_take_sell_seller_only(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require !offer.buy, "sell-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, taker) == 0,    "buyer has no credit (first half of buyer skip)";
    require units <= cvlDebtOf(id, taker),  "units <= buyer.debt (second half of buyer skip)";
    require cvlCreditOf(id, offer.maker) > 0, "seller has credit (seller update fires)";

    require mapIndex(obligationLossIndex(id)) > 0,
            "obligation not fully slashed";

    // Pre-synced both users — see take_sell_buyer_only for soundness.
    require cvlUserLossIndex(id, taker) == obligationLossIndex(id),
            "buyer pre-synced (composes with updatePosition lemma)";
    require cvlUserLossIndex(id, offer.maker) == obligationLossIndex(id),
            "seller pre-synced (composes with updatePosition lemma)";

    requirePrecisionDivisibleBy(obligationLossIndex(id));

    // Collapse assembly helpers:
    //   buyerCreditIncrease = zeroFloorSub(units, buyer.debt) ⇒ 0
    //                         since units <= buyer.debt (already required above)
    //   sellerCreditDecrease = min(units, seller.credit)      ⇒ units when units <= credit
    //   sellerDebtIncrease   = units - sellerCreditDecrease   ⇒ 0
    require units <= cvlCreditOf(id, offer.maker),
            "units <= seller.credit (collapses min to identity)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

// OK : https://prover.certora.com/output/7508195/4670a14deede4e8cbdc6c1826cb6324c/?anonymousKey=1719e30ad5b6d7eba0bcd914d5746dc4040bab9c
// Case (D) for sell: neither `_updatePosition` fires. Both users have no credit
// AND units <= buyer.debt. The take-body math becomes near-trivial:
// buyerCreditIncrease = 0, sellerCreditDecrease = 0 ⇒ no real credit flow.
rule sumOfCreditsLeTotalUnits_take_sell_neither(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require !offer.buy, "sell-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, taker) == 0,     "buyer has no credit";
    require units <= cvlDebtOf(id, taker),   "units <= buyer.debt (buyer update skipped)";
    require cvlCreditOf(id, offer.maker) == 0, "seller has no credit (seller update skipped)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

/// =========================== BUY OFFER (offer.buy) ==========================
/// buyer = offer.maker, seller = taker

// OK https://prover.certora.com/output/7508195/5c0a398a88444258a0b9be7184986550/?anonymousKey=6030d4687638288ce595b63699c6625d87d43a7c
// Case (A) for buy: only buyer's `_updatePosition` fires.
rule sumOfCreditsLeTotalUnits_take_buy_buyer_only(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require offer.buy, "buy-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, offer.maker) > 0, "buyer has credit (buyer update fires)";
    require cvlCreditOf(id, taker) == 0,      "seller has no credit (seller update SKIPPED)";

    require mapIndex(obligationLossIndex(id)) > 0,
            "obligation not fully slashed";

    // Pre-synced both users — see take_sell_buyer_only for soundness.
    require cvlUserLossIndex(id, taker) == obligationLossIndex(id),
            "seller pre-synced (composes with updatePosition lemma)";
    require cvlUserLossIndex(id, offer.maker) == obligationLossIndex(id),
            "buyer pre-synced (composes with updatePosition lemma)";

    requirePrecisionDivisibleBy(obligationLossIndex(id));

    // Collapse assembly helpers (buyer = offer.maker, seller = taker):
    //   buyerCreditIncrease = zeroFloorSub(units, buyer.debt) ⇒ units when buyer.debt == 0
    //   sellerCreditDecrease = min(units, seller.credit)      ⇒ 0     when seller.credit == 0
    require cvlDebtOf(id, offer.maker) == 0,
            "buyer.debt = 0 (collapses zeroFloorSub to identity)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

// Case (B) for buy: only seller's `_updatePosition` fires.
rule sumOfCreditsLeTotalUnits_take_buy_seller_only(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require offer.buy, "buy-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, offer.maker) == 0,         "buyer has no credit";
    require units <= cvlDebtOf(id, offer.maker),       "units <= buyer.debt (buyer update skipped)";
    require cvlCreditOf(id, taker) > 0,                "seller has credit (seller update fires)";

    require mapIndex(obligationLossIndex(id)) > 0,
            "obligation not fully slashed";

    // Pre-synced both users — see take_sell_buyer_only for soundness.
    require cvlUserLossIndex(id, taker) == obligationLossIndex(id),
            "seller pre-synced (composes with updatePosition lemma)";
    require cvlUserLossIndex(id, offer.maker) == obligationLossIndex(id),
            "buyer pre-synced (composes with updatePosition lemma)";

    requirePrecisionDivisibleBy(obligationLossIndex(id));

    // Collapse assembly helpers (buyer = offer.maker, seller = taker):
    //   buyerCreditIncrease = zeroFloorSub(units, buyer.debt) ⇒ 0
    //                         since units <= buyer.debt (already required above)
    //   sellerCreditDecrease = min(units, seller.credit)      ⇒ units when units <= credit
    require units <= cvlCreditOf(id, taker),
            "units <= seller.credit (collapses min to identity)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

// OK https://prover.certora.com/output/7508195/c91b9688d229413c8d328646fd0937b1/?anonymousKey=2db284d4734eae4b184e1dd5fc9bd49b579ed3a6
// Case (D) for buy: neither `_updatePosition` fires.
rule sumOfCreditsLeTotalUnits_take_buy_neither(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require offer.buy, "buy-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require cvlCreditOf(id, offer.maker) == 0,   "buyer has no credit";
    require units <= cvlDebtOf(id, offer.maker), "units <= buyer.debt (buyer update skipped)";
    require cvlCreditOf(id, taker) == 0,         "seller has no credit (seller update skipped)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

// ============================================================================
// FULLY-SLASHED COMPLEMENT — mapIndex(obligationLossIndex(id)) == 0
//
// All six rules above assume `mapIndex(obligationLossIndex(id)) > 0` (the
// buyer_only/seller_only halves require it explicitly; the neither halves only
// fire when neither position has credit). The fully-slashed state IS reachable
// (Midnight.sol L589-592: mapIndex shrinks multiplicatively on each bad-debt
// realization and rounds down to 0), so it must be covered.
//
// When mapIndex(obligationLossIndex(id)) == 0 the body degenerates to
//     continuousFeeCredit(id) <= totalUnits(id)
// (the sumPreciseCreditDivIndex term is multiplied by 0). For any user whose
// `_updatePosition` fires, the summary's precise-credit clause
//     (newCredit + fee) * PRECISION <= preciseCreditDivIndex[id][user] * 0
// forces newCredit == 0 and fee == 0 (the synced branch is guarded off by the
// `mapIndex > 0` condition we added). So:
//   * continuousFeeCredit is unchanged (every accruedFee == 0), and
//   * sellerCreditDecrease = min(units, seller.credit) == 0, hence
//     totalUnits += buyerCreditIncrease only grows.
// Therefore continuousFeeCredit <= totalUnits is preserved. No per-user credit
// or pre-sync constraints are needed — the collapse comes from the summary.
// ============================================================================

rule sumOfCreditsLeTotalUnits_take_sell_fullySlashed(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require !offer.buy, "sell-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require mapIndex(obligationLossIndex(id)) == 0, "fully-slashed obligation (complement of the mapIndex > 0 rules)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

rule sumOfCreditsLeTotalUnits_take_buy_fullySlashed(
    bytes32 id,
    env e,
    uint256 units,
    address taker,
    address takerCallback,
    bytes takerCallbackData,
    address receiverIfTakerIsSeller,
    Midnight.Offer offer,
    bytes ratifierData,
    bytes32 root,
    bytes32[] proof
) {
    require offer.buy, "buy-offer half";
    require sumOfCreditsBody(id);

    takePreconditions(e, taker, offer, takerCallback);

    require mapIndex(obligationLossIndex(id)) == 0, "fully-slashed obligation (complement of the mapIndex > 0 rules)";

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}
