// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function obligationLossIndex(bytes32) external returns (uint128) envfree;

    /// PRICE / ORACLE ///
    function _.price() external => NONDET;

    /// MUL/DIV — function summaries that compute the exact value in mathint.
    // NOTE: kept as CVL summaries (not NONDET) because the soundness of
    // sumOfCreditsLeTotalUnits_{withdraw,take} depends on the exact relationship
    // newCredit ≈ oldCredit * mapIndex(obligation) / mapIndex(user) inside
    // updatePositionView, which gives newD ≤ oldD in updateCreditDivIndex.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    /// MISC INTERNALS irrelevant to credit / loss-index tracking ///
    // The external `toId` summary only fires for cross-contract calls; `withdraw`
    // calls `touchObligation` -> `toId` -> `IdLib.toId` internally, so we also
    // NONDET the IdLib hashing path (keccak256 over abi.encodePacked of a struct
    // with a dynamic array — the kind of hashing-heavy code the prover struggles
    // with). Same for `offerTreeTypeHash`.
    function toId(Midnight.Obligation) external returns (bytes32) => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;

    // `touchObligation` is `public`. The internal-call summary fires when
    // `withdraw`/`take`/etc. call it from within Midnight; the external one
    // catches direct EOA→Midnight invocations. NONDET'ing it skips the
    // collateralParams loop and ObligationState fee initialization on the
    // fresh-obligation branch, which the prover otherwise has to model in
    // full even though none of those writes trigger our hooks.
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

    /// EXTERNAL TOKEN CALLS — defensive, redundant with SafeTransferLib NONDET. ///
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

definition PASSIVE_FEE_RECIPIENT() returns address = 0x7e3dce7c19791d65d67ef7ce3c42d2b7fe6fecb1;

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

/// GHOST preciseCreditDivIndex ///

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


/// HELPER FUNCTIONS ///

// Map index to 1-index, for easier math. 
definition mapIndex(mathint index) returns mathint = 2 ^ 128 - 1 - index;

definition cvlCreditOf(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].credit;

definition cvlUserLossIndex(bytes32 id, address owner) returns uint128 = currentContract.position[id][owner].lossIndex;

// Body of the sumOfCreditsLeTotalUnits invariant. Pulled out as a definition
// so it can be referenced identically by the strong invariant and the
// dedicated lemma rules for withdraw and take.
definition sumOfCreditsBody(bytes32 id) returns bool =
    sumPreciseCreditDivIndex[id] * mapIndex(obligationLossIndex(id))
    + PRECISION * continuousFeeCredit(id)
    <= PRECISION * totalUnits(id);

/// HOOKS ///

function updateCreditDivIndex(bytes32 id, address owner, uint128 newCredit, uint128 newIndex) {
    mathint ownerLossIndex = mapIndex(newIndex);
    require ownerLossIndex > 0 => PRECISION * newCredit % ownerLossIndex == 0,
            "PRECISION absorbs ownerLossIndex";
    mathint oldD = preciseCreditDivIndex[id][owner];
    mathint newD = ownerLossIndex == 0 ? 0 : PRECISION * newCredit / ownerLossIndex;
    preciseCreditDivIndex[id][owner] = newD;
    sumPreciseCreditDivIndex[id] = sumPreciseCreditDivIndex[id] + newD - oldD;
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

/// INVARIANTS ///

strong invariant preciseCreditCorrect(bytes32 id, address owner)
    checkCreditDivInvariant(id, owner);

// Main invariant. `withdraw` and `take` are filtered out and proved by
// the dedicated lemma rules below, because they timed out the SMT solver
// when handled inside the strong-invariant machinery.
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

// The obligation loss index cannot be larger than the user loss index.
strong invariant obligationLossIndexLeqUserLossIndex(bytes32 id, address owner)
    mapIndex(obligationLossIndex(id)) <= mapIndex(cvlUserLossIndex(id, owner));


/*
/// DEDICATED LEMMA RULES ///
//
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
    // itself is verified by `OnlyAuthorizedCanChange.spec`.
    require onBehalf == e.msg.sender;

    // `withdraw` only mutates `onBehalf`'s position. `receiver` only
    // receives a NONDET'd safeTransfer, so no witness needed.
    requireInvariant preciseCreditCorrect(id, onBehalf);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, onBehalf);
    require mapIndex(obligationLossIndex(id)) > 0;
    require mapIndex(cvlUserLossIndex(id, onBehalf)) > 0;

    withdraw(e, obligation, units, onBehalf, receiver);

    assert sumOfCreditsBody(id);
}

rule sumOfCreditsLeTotalUnits_take(
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
    require !offer.buy;
    require sumOfCreditsBody(id);

    // `take` mutates both `taker` and `offer.maker`. `receiverIfTakerIsSeller`
    // only receives a NONDET'd transfer, so no witness needed.
    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}

rule sumOfCreditsLeTotalUnits_take2(
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
    require offer.buy;
    require sumOfCreditsBody(id);

    // `take` mutates both `taker` and `offer.maker`. `receiverIfTakerIsSeller`
    // only receives a NONDET'd transfer, so no witness needed.
    requireInvariant preciseCreditCorrect(id, taker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, taker);
    requireInvariant preciseCreditCorrect(id, offer.maker);
    requireInvariant obligationLossIndexLeqUserLossIndex(id, offer.maker);

    take(e, units, taker, takerCallback, takerCallbackData,
         receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert sumOfCreditsBody(id);
}
*/