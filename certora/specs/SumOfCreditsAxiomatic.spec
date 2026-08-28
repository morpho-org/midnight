// SPDX-License-Identifier: GPL-2.0-or-later
//

import "MulDivAxioms.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint128) envfree;
    function lossFactor(bytes32) external returns (uint128) envfree;

    /// SUMMARY OF updatePositionView -- see file header for soundness argument. ///
    function Midnight.updatePositionView(Midnight.Market memory obligation, bytes32 id, address user) internal returns (uint128, uint128, uint128) with(env e) => summaryUpdatePositionView(e, id, user);

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// MUL/DIV — exact mathint summaries (still needed for the parts of
    /// withdraw / take outside `updatePositionView`, e.g. the proportional
    /// pendingFee adjustment and the take buyer-fee accrual).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    /// MISC INTERNALS irrelevant to credit / loss-index tracking. ///
    function IdLib.toId(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function touchMarket(Midnight.Market) external returns (bytes32) => NONDET;
    function Midnight.touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.tGet(uint256, bytes32, address) internal returns (bool) => NONDET;
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;

    /// SAFE TRANSFERS ///
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// EXTERNAL CALLBACKS — prevent havoc of ghosts and variables in callbacks.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => NONDET;
    function _.onLiquidate(address, bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes, uint256) external => NONDET;
    function _.onFlashLoan(address, address[], uint256[], bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
}

/// GHOSTS ///

persistent ghost mathint PRECISION {
    axiom PRECISION > 0;
}

ghost mapping(bytes32 => mathint) sumPreciseCreditDivIndex {
    init_state axiom forall bytes32 id. sumPreciseCreditDivIndex[id] == 0;
    axiom forall bytes32 id. sumPreciseCreditDivIndex[id] >= 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) preciseCreditDivIndex {
    init_state axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] == 0;
    axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] >= 0;
}

// Instead of using the builtin `*`, which requires unstable non-linear arithemetic, we
// use the uninterpreted function `multiply` and only instantiate those axioms we need for proving.
// `multiply(a, b)` IS the product `a * b` declared as an uninterpreted function.
persistent ghost multiply(mathint, mathint) returns mathint {
    axiom forall mathint a. forall mathint b. (a > 0 && b > 0) => multiply(a, b) > 0;
    axiom forall mathint a. multiply(a, 0) == 0;
    axiom forall mathint b. multiply(0, b) == 0;
}

// Distributivity axiom.
definition axiomDistributivity(mathint a, mathint b, mathint c) returns bool = multiply(a + b, c) == multiply(a, c) + multiply(b, c);

// Symmetry axiom over associativity.
definition axiomAssocComm(mathint a, mathint b, mathint c) returns bool = multiply(multiply(a, b), c) == multiply(multiply(a, c), b);

// Linear order axiom for multiplication with positive constants.
definition axiomLeMulPos(mathint a, mathint b, mathint c) returns bool = c > 0 => ((a <= b) <=> (multiply(a, c) <= multiply(b, c)));

// The following is RoundsDown axiom stated using the `multiply` function.
definition axiomMathMulDivDownRoundsDownMultiply(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 => multiply(mathMulDivDown(a, b, d), d) <= multiply(a, b);

definition axiomMathMulDivDownRoundsDownMultiplySymm(mathint a, mathint b, mathint d) returns bool = a >= 0 && b >= 0 => multiply(d, mathMulDivDown(a, b, d)) <= multiply(b, a);

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0 || a * b >= 2 ^ 256) {
        revert();
    }
    require axiomMathMulDivDownZeroA(b, d), "axiom";
    require axiomMathMulDivDownZeroB(a, d), "axiom";
    require axiomMathMulDivDownRoundsDownMultiply(a, b, d), "axiom";
    require axiomMathMulDivDownRoundsDownMultiplySymm(a, b, d), "axiom";
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (d == 0 || a * b + d - 1 >= 2 ^ 256) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
}

/// HELPER DEFINITIONS ///

definition mapIndex(mathint index) returns mathint = 2 ^ 128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;

definition cvlLastLossFactor(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lastLossFactor;

definition cvlPendingFeeOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].pendingFee;

definition cvlLastAccrualOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lastAccrual;

// Body of the strong invariant. The aggregate product is routed through the
// uninterpreted `multiply` (== sumPreciseCreditDivIndex[id] * mapIndex(...)).
definition sumOfCreditsBody(bytes32 id) returns bool = multiply(sumPreciseCreditDivIndex[id], mapIndex(lossFactor(id))) <= multiply(totalUnits(id), PRECISION) - multiply(continuousFeeCredit(id), PRECISION);

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    mathint oldCDI = preciseCreditDivIndex[id][owner];
    mathint value;

    // We require there is a value such that
    //    value * ownerLossIndex == newCredit * PRECISION.
    // This is sound because we can assume PRECISION to be large enough to
    // be divisible by ownerLossIndex.
    require ownerLossIndex > 0 => multiply(value, ownerLossIndex) == multiply(newCredit, PRECISION), "PRECISION is divisible by ownerLossIndex";

    mathint newCDI = (ownerLossIndex == 0 || newCredit == 0) ? 0 : value;
    preciseCreditDivIndex[id][owner] = newCDI;
    mathint oldSum = sumPreciseCreditDivIndex[id];
    sumPreciseCreditDivIndex[id] = oldSum + newCDI - oldCDI;

    // require distributivity axioms to help prover
    mathint lossIndex = mapIndex(lossFactor(id));
    require axiomDistributivity(oldSum, newCDI, lossIndex), "axiom";
    require axiomDistributivity(oldSum + newCDI - oldCDI, oldCDI, lossIndex), "axiom";
}

function checkCreditDivInvariant(bytes32 id, address owner) returns bool {
    uint128 credit = cvlCreditOf(id, owner);
    uint128 userIndex = cvlLastLossFactor(id, owner);
    mathint mappedIndex = mapIndex(userIndex);

    // Per-user invariant stays in REAL-product form: it is per-user (cheap) and
    // the hook's division-exactness genuinely needs real arithmetic. Abstracting
    // it to multiply weakened this ASSUMED invariant enough to make a
    // fully-slashed store (mapIndex==0, credit!=0) reachable, breaking the hook
    // assert. Only the AGGREGATE (sumOfCreditsBody) is abstracted.
    return mappedIndex == 0 || credit == 0 ? preciseCreditDivIndex[id][owner] == 0 : multiply(preciseCreditDivIndex[id][owner], mappedIndex) == multiply(credit, PRECISION);
}

hook Sstore position[KEY bytes32 id][KEY address owner].credit uint128 newCredit (uint128 oldCredit) {
    updateCreditDivIndex(id, owner, newCredit, cvlLastLossFactor(id, owner));
    if (newCredit > oldCredit) {
        require axiomDistributivity(oldCredit, newCredit - oldCredit, PRECISION), "axiom";
    } else {
        require axiomDistributivity(newCredit, oldCredit - newCredit, PRECISION), "axiom";
    }
}

hook Sstore position[KEY bytes32 id][KEY address owner].lastLossFactor uint128 newIndex (uint128 oldIndex) {
    updateCreditDivIndex(id, owner, cvlCreditOf(id, owner), newIndex);
}

hook Sstore marketState[KEY bytes32 id].totalUnits uint128 newTotal (uint128 oldTotal) {
    if (newTotal > oldTotal) {
        require axiomDistributivity(oldTotal, newTotal - oldTotal, PRECISION), "axiom";
    } else {
        require axiomDistributivity(newTotal, oldTotal - newTotal, PRECISION), "axiom";
    }
}

/// SUMMARY OF updatePositionView ///
//
// Returns nondet (newCredit, newPendingFee, fee) constrained by the
// inequalities proved in UpdatePositionView.spec
// (rule `updatePositionViewReflectedByIndex`).
function summaryUpdatePositionView(env e, bytes32 id, address user) returns (uint128, uint128, uint128) {
    uint128 oldCredit = cvlCreditOf(id, user);
    uint128 oldPendingFee = cvlPendingFeeOf(id, user);
    uint128 oldLastAccrual = cvlLastAccrualOf(id, user);

    require to_mathint(e.block.timestamp) >= to_mathint(oldLastAccrual), "time is non-decreasing";

    uint128 newCredit;
    uint128 newPendingFee;
    uint128 fee;

    require newCredit <= oldCredit, "slashing only decreases credit";
    require newPendingFee <= oldPendingFee, "fee deduction only decreases pending";
    require fee <= oldPendingFee, "fee bounded by pending (UpdatePositionView.spec)";

    // The touched user's pre-term lower bound (updatePositionView slashing bound).
    // Kept in REAL-product form (per-user, cheap); the rule grounds the matching
    // multiply(Dpre, M) to this same product.
    //require (newCredit + fee) * PRECISION <= preciseCreditDivIndex[id][user] * mapIndex(lossFactor(id)), "newCredit (with fees) bounded by precise credit (UpdatePositionView.spec)";
    require multiply(newCredit, PRECISION) + multiply(fee, PRECISION) <= multiply(preciseCreditDivIndex[id][user], mapIndex(lossFactor(id))), "newCredit (with fees) bounded by precise credit (UpdatePositionView.spec)";

    // A fully-slashed user (lossIndex == max, mapIndex == 0) gets credit and fee 0: updatePositionView's
    // postSlashCredit ternary returns 0 when _lossIndex == max (Midnight.sol:752), and postSlashPending/fee
    // then collapse to 0 too. Without this the summary admits newCredit > 0 for a fully-slashed user, which
    // breaks the "division is exact" hook (0 == newCredit * PRECISION).
    require mapIndex(cvlLastLossFactor(id, user)) == 0 => (newCredit == 0 && fee == 0), "fully-slashed user gets 0 credit/fee (updatePositionView _lossIndex == max guard)";

    // Fully-slashed OBLIGATION also forces 0, independent of whether this user's own
    // lastLossFactor has synced yet: postSlashCredit = credit.mulDivDown(mapIndex(lossFactor(id)),
    // mapIndex(_lastLossFactor)) (Midnight.sol:820-821) has a ZERO NUMERATOR whenever
    // mapIndex(lossFactor(id)) == 0, so mulDivDown returns exactly 0 regardless of the
    // (nonzero) divisor -- and postSlashPendingFee/fee then cascade to 0 too (L824-830).
    // Without this, a "stale" user (obligation fully slashed, user not yet synced) can
    // leak nonzero newCredit/fee through the summary.
    require mapIndex(lossFactor(id)) == 0 => (newCredit == 0 && fee == 0), "fully-slashed obligation gets 0 credit/fee regardless of user sync (mulDivDown zero-numerator)";

    // help solver to reason about fee and distributivity.
    require axiomDistributivity(fee, continuousFeeCredit(id), PRECISION), "axiom";

    return (newCredit, newPendingFee, fee);
}

/// INVARIANTS ///

strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

strong invariant lossFactorLeqLastLossFactor(bytes32 id, address owner)
    mapIndex(lossFactor(id)) <= mapIndex(cvlLastLossFactor(id, owner))
    {
        preserved liquidate(Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) with (env e) {
            require forall mathint a. forall mathint b. forall mathint d. axiomMathMulDivDownArgumentLesserThanDenominatorB(a, b, d), "axiom";
        }
    }

// Parametric coverage of the sum invariant for all methods EXCEPT withdraw and
// take, which are handled by their dedicated rules (sumOfCreditsLeTotalUnits_withdraw
// here, and the SumOfCreditsSummaryTake.spec split for take).
strong invariant sumOfCreditsLeTotalUnits(bytes32 id)
    sumOfCreditsBody(id)
    filtered { f -> f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector } {
        preserved claimContinuousFee(Midnight.Market market, uint256 amount, address receiver) with (env e) {
            require axiomDistributivity(continuousFeeCredit(id) - amount, amount, PRECISION), "axiom";
            require axiomDistributivity(totalUnits(id) - amount, amount, PRECISION), "axiom";
        }
    
        preserved updatePosition(Midnight.Market market, address user) with (env e) {
            requireInvariant preciseCreditCorrect(id, user);
            requireInvariant lossFactorLeqLastLossFactor(id, user);
        }
    
        preserved withdraw(Midnight.Market market, uint256 units, address onBehalf, address receiver) with (env e) {
            requireInvariant preciseCreditCorrect(id, onBehalf);
            requireInvariant lossFactorLeqLastLossFactor(id, onBehalf);
        }
    }

// LIQUIDATE — the OPPOSITE of withdraw/take for multiply. Liquidate never
// calls _updatePosition or touches any user's credit (it writes the *obligation*
// lossFactor, not per-user position.lastLossFactor), so no hook fires and `sum` is
// UNCHANGED. Instead the obligation factor M rescales:
//     mapIndex(new) = mulDivDown(mapIndex(old), tu - badDebt, tu)   (Midnight.sol:589)
//     continuousFeeCredit_new = mulDivDown(cf_old, mapIndex(new), mapIndex(old)) (L594)
//     tu_new = tu_old - badDebt                                     (L593)
// The aggregate `multiply(sum, M)` therefore changes via its 2ND argument,
// which additivity cannot express. So here we do the inverse of withdraw/take:
// GROUND the aggregate back to a real product (pre and post). That re-exposes
// sum*M_old and sum*M_new, but liquidate ALREADY discharges those via the
// ghostMulDivDown rounds-down bound (it verifies in the parametric invariant),
// and `sum` is a single snapshot here (not the touched-user delta), so the
// withdraw-style NIA divergence does not occur.
rule sumOfCreditsLeTotalUnitsPreservedByLiquidate(bytes32 id, env e, Midnight.Market obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data) {
    require sumOfCreditsBody(id);
    requireInvariant preciseCreditCorrect(id, borrower);
    requireInvariant lossFactorLeqLastLossFactor(id, borrower);

    mathint sumPre = sumPreciseCreditDivIndex[id];
    mathint indexPre = mapIndex(lossFactor(id));
    mathint tuPre = totalUnits(id);
    mathint cfPre = continuousFeeCredit(id);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    mathint indexPost = mapIndex(lossFactor(id));
    mathint tuPost = totalUnits(id);
    mathint cfPost = continuousFeeCredit(id);

    // Real fact (Midnight.sol:649): tuPost==tuPre-badDebt whenever liquidate's update block
    // ran (badDebt>0); when badDebt==0 the block is skipped entirely and tuPost==tuPre, so
    // this identity still gives badDebt==0 correctly either way.
    mathint badDebt = tuPre - tuPost;

    // (C): linear combination of (A) and rearranged (B) (add (A) to -1*(B), i.e.
    // cfPre*indexPost-cfPost*indexPre>=0), then factor via subtraction-distributivity -- both terms
    // on each side share the SAME second argument (indexPost for the tuPre/cfPre pair, indexPre for
    // tuPost/cfPost), which is exactly the shape multiply(a,m)-multiply(b,m)==multiply(a-b,m)
    // needs, so this needs no cancellation, only the additivity already established.
    require axiomDistributivity(cfPre, tuPre - cfPre, indexPost), "axiom";
    require axiomDistributivity(cfPost, tuPost - cfPost, indexPre), "axiom";
    require axiomDistributivity(tuPre - cfPre, cfPre, PRECISION), "axiom";
    require axiomDistributivity(tuPost - cfPost, cfPost, PRECISION), "axiom";

    // The proof requires several steps:

    // From mulDiv axioms for indexPost = indexPre.mulDivDown(tuPost, tuPre):
    // tuPre * indexPost <= tuPost * indexPre
    // From mulDiv axiom for cfPost = cfPre.mulDivDown(indexPost, indexPre):
    // cfPost * indexPre <= cfPre * indexPost
    // Using distributivity above:
    // (tuPre - cfPre) * indexPost <= (tuPost - cfPost) * indexPre  (A)

    // Then the main proof is:
    // sumPre * indexPre <= (tuPre - cfPre) * PRECISION  (sumOfCreditBody Pre)
    // <=>  { indexPost >= 0}
    // sumPre * indexPre * indexPost <= (tuPre - cfPre) * PRECISION * indexPost
    // <=> { 2x associative commutative }
    // sumPre * indexPost * indexPre <= (tuPre - cfPre) * indexPost * PRECISION
    // <=> { (A) multiplied with PRECISION >= 0 }
    // sumPre * indexPost * indexPre <= (tuPost - cfPost) * indexPre * PRECISION
    // <=> { associative, commutative }
    // sumPre * indexPost * indexPre <= (tuPost - cfPost) * PRECISION * indexPre
    // <=> { divide by indexPre >= 0}
    // sumPre * indexPost <= (tuPost - cfPost) * PRECISION  (sumOfCreditBody Post)

    // These are the axioms used in the proof above
    require axiomLeMulPos(multiply(sumPre, indexPre), multiply(tuPre - cfPre, PRECISION), indexPost), "axiom";
    require axiomAssocComm(sumPre, indexPre, indexPost), "axiom";
    require axiomAssocComm(tuPre - cfPre, PRECISION, indexPost), "axiom";
    require axiomLeMulPos(multiply(tuPre - cfPre, indexPost), multiply(tuPost - cfPost, indexPre), PRECISION), "axiom";
    require axiomAssocComm(tuPost - cfPost, indexPre, PRECISION), "axiom";
    require axiomLeMulPos(multiply(sumPre, indexPost), multiply(tuPost - cfPost, PRECISION), indexPre), "axiom";

    assert sumOfCreditsBody(id);
}

rule sumOfCreditsLeTotalUnitsPreservedByTake(bytes32 id, env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require sumOfCreditsBody(id);

    // Determine buyer and seller
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant lossFactorLeqLastLossFactor(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant lossFactorLeqLastLossFactor(id, offer.maker);

    mathint tuPre = totalUnits(id);
    mathint debtPre_b = currentContract.position[id][buyer].debt;

    take(e, offer, ratifierData, units, taker, receiverIfTakerIsSeller, takerCallback, takerCallbackData);
    mathint tuPost = totalUnits(id);

    // Compute the buyer credit increase. Note that updatePosition does
    // not touch debt, so we can use this formula from Midnight.
    mathint buyerCreditIncrease = units > debtPre_b ? units - debtPre_b : 0;

    // We do not have the credit of seller after updatePosition before take,
    // but we can compute sellerCreditDecrease from totalUnits change.
    mathint sellerCreditDecrease = tuPre + buyerCreditIncrease - tuPost;

    // These distributivity axiom is needed because Midnight adds buyer and
    // seller credit at the same time.
    if (buyerCreditIncrease > sellerCreditDecrease) {
        require axiomDistributivity(buyerCreditIncrease - sellerCreditDecrease, sellerCreditDecrease, PRECISION), "axiom";
    } else {
        require axiomDistributivity(sellerCreditDecrease - buyerCreditIncrease, buyerCreditIncrease, PRECISION), "axiom";
    }
    assert sumOfCreditsBody(id);
}
