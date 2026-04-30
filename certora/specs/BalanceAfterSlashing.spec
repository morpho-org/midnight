// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationLossIndex(bytes32) external returns (uint128) envfree;

    // updatePositionView is used in two regular rules but is not envfree (uses block.timestamp).
    // Mark optional to silence the spec syntax warning when verifying parametric/invariant rules
    // that do not exercise it directly. Note: no `memory` location specifier — CVL rejects it
    // on non-library external method declarations.
    function updatePositionView(Midnight.Obligation, bytes32, address) external returns (uint128, uint128, uint128) optional;

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// SAFE TRANSFERS ///
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    /// MUL/DIV — function summaries that compute the exact value in mathint.
    /// This preserves all arithmetic relationships (so updatePositionViewReflectedByIndex
    /// still works) while removing the toUint128/cast overhead inlined around each call.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    /// MISC INTERNALS irrelevant to credit / loss-index tracking ///
    function toId(Midnight.Obligation) external returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    /// EXTERNAL CALLBACKS — collapse path explosion for strong invariants. ///
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
}

definition PASSIVE_FEE_RECIPIENT() returns address = 0x7e3dce7c19791d65d67ef7ce3c42d2b7fe6fecb1;

/// MULDIV FUNCTION SUMMARIES ///
// Compute the exact value in mathint and reject division-by-zero / overflow paths.
// The non-deterministic `overflow` flag is sound: when picked true the call reverts
// and the rule's assertion is not checked on that branch (mirroring real Solidity
// uint256 multiplication overflow). Mirrors the helper already in this spec file
// historically and matches the pattern used in Healthiness.spec.
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

/// GHOST creditAfterSlashingWithPrecision ///

// PRECISION is a (large, abstract) integer that absorbs all rounding error.
// We do not pin its value, only that it's positive and that PRECISION * credit
// is an exact multiple of every userLossIndex we may write.
persistent ghost mathint PRECISION {
    axiom PRECISION > 0;
}

// Ghost mirror of PRECISION * creditOf(id,user) / userLossIndex(id,user), kept exact by the hooks.
ghost mapping(bytes32 => mapping(address => mathint)) preciseCreditDivIndex {
    init_state axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] == 0;

    // this is necessary to help the prover. It's an obvious consequence, but the usum implementation does not reason about quantifiers.
    init_state axiom forall bytes32 id. (usum address user. preciseCreditDivIndex[id][user]) == 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) pendingFeeMirror {
    init_state axiom forall bytes32 id. forall address user. pendingFeeMirror[id][user] == 0;
}

ghost mapping(bytes32 => mapping(address => mathint)) lastAccrualMirror {
    init_state axiom forall bytes32 id. forall address user. lastAccrualMirror[id][user] == 0;
}

/// HELPER FUNCTIONS ///

// Map index to 1-index, for easier math. 
definition mapIndex(mathint index) returns mathint = 2 ^ 128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;

definition cvlUserLossIndex(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lossIndex;

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    require ownerLossIndex > 0 => PRECISION * newCredit % ownerLossIndex == 0, "PRECISION is 2^128!";
    preciseCreditDivIndex[id][owner] = ownerLossIndex == 0 ? 0 : PRECISION * newCredit / ownerLossIndex;
}

function checkCreditDivInvariant(bytes32 id, address owner) returns bool {
    uint128 credit = cvlCreditOf(id, owner);
    uint128 userIndex = cvlUserLossIndex(id, owner);
    mathint mappedIndex = mapIndex(userIndex);
    return mappedIndex == 0 ? preciseCreditDivIndex[id][owner] == 0 : preciseCreditDivIndex[id][owner] * mappedIndex == PRECISION * credit;
}

hook Sstore position[KEY bytes32 id][KEY address owner].credit uint128 newCredit (uint128 oldCredit) {
    updateCreditDivIndex(id, owner, newCredit, cvlUserLossIndex(id, owner));
}

hook Sstore position[KEY bytes32 id][KEY address owner].lossIndex uint128 newIndex (uint128 oldIndex) {
    updateCreditDivIndex(id, owner, cvlCreditOf(id, owner), newIndex);
}

hook Sload uint128 value position[KEY bytes32 id][KEY address owner].pendingFee {
    require pendingFeeMirror[id][owner] == value, "ghost mirror";
}

hook Sload uint128 value position[KEY bytes32 id][KEY address owner].lastAccrual {
    require lastAccrualMirror[id][owner] == value, "ghost mirror";
}

hook Sstore position[KEY bytes32 id][KEY address owner].pendingFee uint128 newPending (uint128 oldPending) {
    pendingFeeMirror[id][owner] = newPending;
}

hook Sstore position[KEY bytes32 id][KEY address owner].lastAccrual uint128 newLast (uint128 oldLast) {
    lastAccrualMirror[id][owner] = newLast;
}

/// invariants ///
strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

strong invariant sumOfCreditsLeTotalUnits(bytes32 id)
    (usum address owner. preciseCreditDivIndex[id][owner]) * mapIndex(obligationLossIndex(id)) + PRECISION * continuousFeeCredit(id) <= PRECISION * totalUnits(id)
{
    preserved updatePosition(Midnight.Obligation obligation, address user) with (env e) {
        requireInvariant preciseCreditCorrect(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant obligationLossIndexLeqUserLossIndex(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant preciseCreditCorrect(id, user);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, user);
    }

    preserved withdraw(Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver) with (env e) {
        requireInvariant preciseCreditCorrect(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant obligationLossIndexLeqUserLossIndex(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant preciseCreditCorrect(id, onBehalf);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, onBehalf);
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
        requireInvariant preciseCreditCorrect(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant obligationLossIndexLeqUserLossIndex(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant preciseCreditCorrect(id, borrower);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, borrower);
    }

    // NOTE: this preserved block was previously stale (used Midnight.Signature) and never
    // matched, so requireInvariant hints were silently dropped on take(). Fixed signature.
    preserved take(
        uint256 obligationUnits,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        Midnight.Offer offer,
        bytes ratifierData,
        bytes32 root,
        bytes32[] proof) with (env e) {
        requireInvariant preciseCreditCorrect(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant obligationLossIndexLeqUserLossIndex(id, PASSIVE_FEE_RECIPIENT());
        requireInvariant preciseCreditCorrect(id, taker);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
        requireInvariant preciseCreditCorrect(id, offer.maker);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);
    }
}

// The obligation loss index cannot be larger than the user loss index.
strong invariant obligationLossIndexLeqUserLossIndex(bytes32 id, address owner)
    mapIndex(obligationLossIndex(id)) <= mapIndex(cvlUserLossIndex(id, owner));

rule updatePositionViewReflectedByIndex(env e, Midnight.Obligation obligation, bytes32 id, address owner) {
    requireInvariant preciseCreditCorrect(id, owner);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, owner);

    uint128 newCredit;
    uint128 newPending;
    uint128 fee;

    mathint preciseCreditBefore = preciseCreditDivIndex[id][owner] * mapIndex(obligationLossIndex(id));
    mathint pendingBefore = pendingFeeMirror[id][owner];
    mathint lastAccrualBefore = lastAccrualMirror[id][owner];

    require e.block.timestamp >= lastAccrualBefore, "Time is increasing";

    newCredit, newPending, fee = updatePositionView(e, obligation, id, owner);

    assert fee <= pendingBefore, "Cannot take more fee than pending";
    assert (newCredit + fee) * PRECISION <= preciseCreditBefore, "newCredit (with fees) is at most precise credit after slashing";
}

rule updatePositionZero(env e, Midnight.Obligation obligation, bytes32 id, address owner) {
    require currentContract.position[id][owner].credit == 0, "Assume no credit";

    uint128 newCredit;
    uint128 newPending;
    uint128 fee;
    newCredit, newPending, fee = updatePositionView(e, obligation, id, owner);

    assert newCredit == 0 && newPending == 0 && fee == 0;
}

invariant pendingFeeLessEqualThanCredit(bytes32 id, address user)
    currentContract.position[id][user].pendingFee <= currentContract.position[id][user].credit;

//invariant pendingFeeLessThanCredit(bytes32 id, address user)
//    currentContract.position[id][user].pendingFee < currentContract.position[id][user].credit || currentContract.position[id][user].pendingFee == 0;
