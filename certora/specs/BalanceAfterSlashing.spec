// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function creditAfterSlashing(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationLossIndex(bytes32) external returns (uint128) envfree;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;

    // Summarize price oracle as NONDET (it is a view function)
    function _.price() external => NONDET;

    // Summarize safeTransfer as NONDET for now (TODO: we could also model them as external)
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Summarize internals irrelevant to credit tracking.
    function toId(Midnight.Obligation) external returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(a * b / d);
}

/// GHOST creditAfterSlashingWithPrecision ///

// precision is an integer that is so large that no rounding error will ever occur.
// A possible value would be 2^128! (factorial).
// We do not restrict the value but only axiomatically say that it's greater 0 and a multiple of each ownerLossIndex.
persistent ghost mathint PRECISION {
    axiom PRECISION > 0;
}

// ghost mapping for PRECISION * creditOf(id,user) / userLossIndex(id,user)
// PRECISION ensures that the division will be without rounding errors.
ghost mapping(bytes32 => mapping(address => mathint)) preciseCreditDivIndex {
    init_state axiom forall bytes32 id. forall address user. preciseCreditDivIndex[id][user] == 0;
    // this is necessary to help the prover. It's an obvious consequence, but the usum implementation does not reason about quantifiers.
    init_state axiom forall bytes32 id. (usum address user. preciseCreditDivIndex[id][user]) == 0;
}

/// HELPER FUNCTIONS ///

// Map index to 1-index, for easier math. 
definition mapIndex(mathint index) returns mathint = 2^128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;
definition cvlUserLossIndex(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lossIndex;

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    require ownerLossIndex > 0 => PRECISION * newCredit % ownerLossIndex == 0, "PRECISION is 2^128!";
    preciseCreditDivIndex[id][owner] = 
        ownerLossIndex == 0 ? 0 : PRECISION * newCredit / ownerLossIndex;
}

function checkCreditDivInvariant(bytes32 id, address owner) returns bool {
    uint128 credit = cvlCreditOf(id,owner);
    uint128 userIndex = cvlUserLossIndex(id,owner);
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

/// invariants ///
strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

strong invariant sumOfCreditsLeTotalUnits(bytes32 id)
    (usum address owner. preciseCreditDivIndex[id][owner]) * mapIndex(obligationLossIndex(id)) <= PRECISION * totalUnits(id)
{
    preserved slash(bytes32 slashid, address user) with (env e) {
    }

    preserved withdraw(Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver) with (env e) {
        requireInvariant preciseCreditCorrect(id, onBehalf);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, onBehalf);
    }

    preserved take(
        uint256 obligationUnits,
        address taker,
        address takerCallback,
        bytes takerCallbackData,
        address receiverIfTakerIsSeller,
        Midnight.Offer offer,
        Midnight.Signature signature,
        bytes32 root,
        bytes32[] proof) with (env e) {
        requireInvariant preciseCreditCorrect(id, taker);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
        requireInvariant preciseCreditCorrect(id, offer.maker);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);
    }

}
// The obligation loss index cannot be larger than the user loss index.
// We only need that if userLossIndex is zero so is obligationLossIndex.
strong invariant obligationLossIndexLeqUserLossIndex(bytes32 id, address owner)
    mapIndex(cvlUserLossIndex(id, owner)) == 0 => mapIndex(obligationLossIndex(id)) == 0;
//    mapIndex(obligationLossIndex(id)) <= mapIndex(cvlUserLossIndex(id, owner));

strong invariant creditAfterSlashingValue(bytes32 id, address owner)
    mapIndex(cvlUserLossIndex(id,owner)) != 0 =>
    (creditAfterSlashing(id, owner) == preciseCreditDivIndex[id][owner] * mapIndex(obligationLossIndex(id)) / PRECISION)
{
    preserved {
        requireInvariant preciseCreditCorrect(id, owner);
        requireInvariant obligationLossIndexLeqUserLossIndex(id, owner);
    }
}
