// SPDX-License-Identifier: GPL-2.0-or-later
//

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationLossIndex(bytes32) external returns (uint128) envfree;

    /// SUMMARY OF updatePositionView -- see file header for soundness argument. ///
    function Midnight.updatePositionView(Midnight.Obligation memory obligation, bytes32 id, address user)
        internal returns (uint128, uint128, uint128) with (env e)
        => summaryUpdatePositionView(e, id, user);

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// MUL/DIV — exact mathint summaries (still needed for the parts of
    /// withdraw / take outside `updatePositionView`, e.g. the proportional
    /// pendingFee adjustment and the take buyer-fee accrual).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    /// MISC INTERNALS irrelevant to credit / loss-index tracking. ///
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
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    /// SAFE TRANSFERS ///
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// EXTERNAL CALLBACKS — prevent havoc of ghosts on unresolved calls in `take`. ///
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;

    /// EXTERNAL TOKEN CALLS — defensive, redundant with SafeTransferLib NONDET. ///
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

/// MULDIV FUNCTION SUMMARIES ///
function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(a * b / d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256((a * b + (d - 1)) / d);
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

/// HELPER DEFINITIONS ///

definition mapIndex(mathint index) returns mathint = 2 ^ 128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;

definition cvlUserLossIndex(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lossIndex;

definition cvlPendingFeeOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].pendingFee;

definition cvlLastAccrualOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lastAccrual;

// Body of the strong invariant. Identical to SumOfCredits.spec.
definition sumOfCreditsBody(bytes32 id) returns bool = sumPreciseCreditDivIndex[id] * mapIndex(obligationLossIndex(id)) + PRECISION * continuousFeeCredit(id) <= PRECISION * totalUnits(id);

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    require ownerLossIndex > 0 => PRECISION * newCredit % ownerLossIndex == 0, "PRECISION absorbs ownerLossIndex";
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
//
// Returns nondet (newCredit, newPendingFee, fee) constrained by the
// inequalities proved in UpdatePositionView.spec
// (rule `updatePositionViewReflectedByIndex`).
//
// `newCredit <= oldCredit` and `newPendingFee <= oldPendingFee` are also
// required: not part of the proven inequalities, but enforced by the real
// `_updatePosition` (which immediately performs `creditDecrease =
// _position.credit - newCredit` and `pendingFeeDecrease = _position.pendingFee
// - newPendingFee`, both of which would underflow otherwise).
function summaryUpdatePositionView(env e, bytes32 id, address user) returns (uint128, uint128, uint128)
{
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
    require (newCredit + fee) * PRECISION <= preciseCreditDivIndex[id][user] * mapIndex(obligationLossIndex(id)), "newCredit (with fees) bounded by precise credit (UpdatePositionView.spec)";

    return (newCredit, newPendingFee, fee);
}

/// INVARIANTS ///

strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

strong invariant obligationLossIndexLeqUserLossIndex(bytes32 id, address owner)
    mapIndex(obligationLossIndex(id)) <= mapIndex(cvlUserLossIndex(id, owner));

// Parametric coverage of the sum invariant for all methods EXCEPT withdraw and
// take, which are handled by their dedicated rules (sumOfCreditsLeTotalUnits_withdraw
// here, and the SumOfCreditsSummaryTake.spec split for take).
strong invariant sumOfCreditsLeTotalUnits(bytes32 id)
    sumOfCreditsBody(id)
    filtered { f ->
        f.selector != sig:withdraw(Midnight.Obligation,uint256,address,address).selector
     && f.selector != sig:take(uint256,address,address,bytes,address,Midnight.Offer,bytes,bytes32,bytes32[]).selector
    }
{
    preserved updatePosition(Midnight.Obligation obligation, address user) with (env e) {
        require mapIndex(obligationLossIndex(id)) > 0;
        requireInvariant preciseCreditCorrect(id, user);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, user);
    }

    preserved liquidate(
        Midnight.Obligation obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        address receiver,
        address callback,
        bytes data
    ) with (env e) {
        requireInvariant preciseCreditCorrect(id, borrower);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, borrower);
    }
}

rule sumOfCreditsLeTotalUnits_withdraw(
    bytes32 id,
    env e,
    Midnight.Obligation obligation,
    uint256 units,
    address onBehalf,
    address receiver
) {
    require sumOfCreditsBody(id);

    // Sound: the auth branch (`onBehalf != msg.sender && isAuthorized[...]`)
    // doesn't change credit/lossIndex math; the property only depends on what
    // the rest of `withdraw` does to position[id][onBehalf]. Authorization
    // itself is verified by OnlyAuthorizedCanChange.spec.
    require onBehalf == e.msg.sender,"auth branch verified separately by OnlyAuthorizedCanChange.spec";

    requireInvariant preciseCreditCorrect(id, onBehalf);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, onBehalf);
    require mapIndex(obligationLossIndex(id)) > 0,"obligation not fully slashed (else body is 0 <= constFee.PRECISION)";
    require mapIndex(cvlUserLossIndex(id, onBehalf)) > 0,"user not fully slashed (consequence of obligation <= user index)";

    withdraw(e, obligation, units, onBehalf, receiver);

    assert sumOfCreditsBody(id);
}

// ── Fully-slashed complement: mapIndex(obligationLossIndex(id)) == 0 ──
//
// The `preserved updatePosition` block and the `_withdraw` rule both assume
// `mapIndex(obligationLossIndex(id)) > 0`. That assumption is NOT free:
// slashing can drive the obligation index up to type(uint128).max. In
// Midnight.sol (L589-592):
//     newLossIndex = max - mapIndex(oldLossIndex) * (totalUnits - badDebt) / totalUnits
// so mapIndex(newLossIndex) = mapIndex(old) * (totalUnits - badDebt) / totalUnits
// (rounded down), which reaches 0 when badDebt == totalUnits or by rounding.
// Hence the fully-slashed state is reachable and must be covered separately.
//
// When mapIndex(obligationLossIndex(id)) == 0 the body degenerates to
//     continuousFeeCredit(id) <= totalUnits(id)
// (the sumPreciseCreditDivIndex term is multiplied by 0). The summary returns
// newCredit == 0 and fee == 0 in this case (the precise-credit clause
// `(newCredit + fee) * PRECISION <= preciseCreditDivIndex * 0` forces it), so
// neither `updatePosition` nor `withdraw` increases continuousFeeCredit, and
// totalUnits is unchanged (updatePosition) or can only shrink with a matching
// credit decrease (withdraw, which reverts unless units == 0 once credit is 0).
rule sumOfCreditsLeTotalUnits_updatePosition_fullySlashed(
    bytes32 id,
    env e,
    Midnight.Obligation obligation,
    address user
) {
    require sumOfCreditsBody(id);
    require mapIndex(obligationLossIndex(id)) == 0, "fully-slashed obligation (complement of the preserved block)";

    requireInvariant preciseCreditCorrect(id, user);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, user);

    updatePosition(e, obligation, user);

    assert sumOfCreditsBody(id);
}

rule sumOfCreditsLeTotalUnits_withdraw_fullySlashed(
    bytes32 id,
    env e,
    Midnight.Obligation obligation,
    uint256 units,
    address onBehalf,
    address receiver
) {
    require sumOfCreditsBody(id);
    require onBehalf == e.msg.sender, "auth branch verified separately by OnlyAuthorizedCanChange.spec";

    requireInvariant preciseCreditCorrect(id, onBehalf);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, onBehalf);
    require mapIndex(obligationLossIndex(id)) == 0, "fully-slashed obligation (complement of sumOfCreditsLeTotalUnits_withdraw)";

    withdraw(e, obligation, units, onBehalf, receiver);

    assert sumOfCreditsBody(id);
}

// Monolithic take_sell — superseded by the 4-way split in
// SumOfCreditsSummaryTake.spec (take_sell_buyer_only / _seller_only /
// _neither). Kept here commented out for reference.
/*
rule sumOfCreditsLeTotalUnits_take_sell(
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
    require !offer.buy, "sell-offer half of the case split (taker buys)";
    require sumOfCreditsBody(id);

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}
*/


/*
rule sumOfCreditsLeTotalUnits_take_buy(
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
    require offer.buy, "buy-offer half of the case split (taker sells)";
    require sumOfCreditsBody(id);

    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}*/
