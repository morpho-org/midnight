// SPDX-License-Identifier: GPL-2.0-or-later

using Havoc as callback;
using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function _.price() external => CVL_price(calledContract) expect(uint256);
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
    function _.onRatify(Midnight.Offer offer, bytes32 root, bytes data) external => genericCallbackBytes32() expect(bytes32);

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => CVL_mulDivUp(a, b, d);

    // function UtilsLib.tExchange(uint256 baseSlot, bytes32 key1, address key2, bool value) internal returns (bool) => cvlTExchange(baseSlot, key1, key2, value);
    // function UtilsLib.tGet(uint256 baseSlot, bytes32 key1, address key2) internal returns (bool) => cvlTGet(baseSlot, key1, key2);
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;

    function _.havocAll() external => HAVOC_ALL;

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect(bool);
    function _.onBuy(bytes32 id, Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onSell(bytes32 id, Midnight.Obligation obligation, address seller, uint256 sellerAssets, uint256 units, bytes data) external => genericCallbackBytes32() expect(bytes32);
    function _.onRepay(bytes32 id, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) external => genericCallback() expect void;
    function _.onLiquidate(bytes32 id, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallback() expect void;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => genericCallback() expect void;
}

persistent ghost bytes32 globalId;

persistent ghost address globalBorrower;

// Accumulator, false if at least one callback started with the lock off.
ghost bool lockedBeforeCallbacks;

// Accumulator, false if at least one callback started with the lock on.
ghost bool unlockedBeforeCallbacks;

// Non-persistent as calls can trigger oracle updates
ghost CVL_price(address) returns uint256;

ghost CVL_msb(uint128) returns uint256;

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

persistent ghost mapping(uint256 => mapping(bytes32 => mapping(address => bool))) lockGhost;

// This and cvlTGet are required due to transient storage analysis failure.
function cvlTExchange(uint256 baseSlot, bytes32 key1, address key2, bool value) returns bool {
    bool prev = lockGhost[baseSlot][key1][key2];
    lockGhost[baseSlot][key1][key2] = value;
    return prev;
}

function cvlTGet(uint256 baseSlot, bytes32 key1, address key2) returns bool {
    return lockGhost[baseSlot][key1][key2];
}

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function genericCallback() {
    address dummy;
    env e;
    bool lockedBefore = liquidationLocked(e, globalId, globalBorrower);
    bool savedLockedBeforeCallbacks = lockedBeforeCallbacks && lockedBefore;
    bool savedUnlockedBeforeCallbacks = unlockedBeforeCallbacks && !lockedBefore;

    callback.callHavoc(e, dummy);

    // the callback havocs the global variables lockedBeforeCallbacks and unlockedBeforeCallbacks, so we restore them using the saved values in the local variables.
    lockedBeforeCallbacks = savedLockedBeforeCallbacks;
    unlockedBeforeCallbacks = savedUnlockedBeforeCallbacks;

    require liquidationLocked(e, globalId, globalBorrower) == lockedBefore, "lock preserved by callback";
}

function genericCallbackBool() returns (bool) {
    bool result;
    genericCallback();
    return result;
}

function genericCallbackBytes32() returns (bytes32) {
    bytes32 result;
    genericCallback();
    return result;
}

// A locked borrower is not liquidatable.
// Together with notLiquidatableImpliesLiquidateReverts in Liquidate.spec, this implies liquidate reverts when locked.
rule notLiquidatableWhenLocked(env e, Midnight.Obligation obligation, address borrower) {
    bytes32 id = summaryToId(obligation);
    require liquidationLocked(e, id, borrower), "borrower is locked before call";

    assert !isLiquidatable(e, obligation, id, borrower), "locked borrower is not liquidatable";
}

// During a take, liquidation of the seller on the sold obligation is locked.
rule sellerAlwaysLockedInTakeCallbacks(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    globalId = summaryToId(offer.obligation);
    globalBorrower = offer.buy ? taker : offer.maker;
    lockedBeforeCallbacks = true;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert lockedBeforeCallbacks;
}

// The 5 rules below show that the only liquidation lock state that is not strongly preserved is a disabled lock for the seller of an obligation.
// That disabled lock state is weakly preserved, and all external calls in it begin with the lock as enabled.

// An enabled liquidation lock is preserved during and after calls.
rule lockPreservation(method f, env e, calldataarg args, bytes32 id, address borrower) {
    globalId = id;
    globalBorrower = borrower;
    require liquidationLocked(e, globalId, globalBorrower);
    lockedBeforeCallbacks = true;

    f(e, args);
    assert lockedBeforeCallbacks, "lock preserved during call";
    assert liquidationLocked(e, globalId, globalBorrower), "lock preserved after call";
}

// A disabled liquidation lock is preserved during and after calls except in take.
rule unlockedLockPreservation(method f, env e, calldataarg args, bytes32 id, address borrower) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector } {
    globalId = id;
    globalBorrower = borrower;
    require !liquidationLocked(e, globalId, globalBorrower);
    unlockedBeforeCallbacks = true;

    f(e, args);
    assert unlockedBeforeCallbacks, "disabled lock preserved during call";
    assert !liquidationLocked(e, globalId, globalBorrower), "disabled lock preserved after call";
}

// Except for the lock on the seller in the taken obligation, any disabled liquidation lock is preserved during and after a take.
rule otherUnlockedPairsStayUnlockedInTakeCallbacks(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof, bytes32 id, address borrower) {
    globalId = id;
    globalBorrower = borrower;
    address otherBorrower = offer.buy ? taker : offer.maker;
    require globalId != summaryToId(offer.obligation) || otherBorrower != globalBorrower, "pair differs from seller on sold obligation";
    require !liquidationLocked(e, globalId, globalBorrower), "pair is unlocked before call";
    unlockedBeforeCallbacks = true;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);
    assert unlockedBeforeCallbacks;
    assert !liquidationLocked(e, globalId, globalBorrower), "pair is unlocked after call";
}

// After a take, a seller cannot be liquidated on the sold obligation.
rule sellerNotLiquidatableAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    globalId = summaryToId(offer.obligation);
    globalBorrower = offer.buy ? taker : offer.maker;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert !isLiquidatable(e, offer.obligation, globalId, globalBorrower), "seller is not liquidatable after take";
}

// The seller disabled lock is weakly preserved
rule sellerUnlockedAfterTake(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    globalId = summaryToId(offer.obligation);
    globalBorrower = offer.buy ? taker : offer.maker;
    require !liquidationLocked(e, globalId, globalBorrower), "seller is not locked before call";

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, ratifierData, root, proof);

    assert !liquidationLocked(e, globalId, globalBorrower), "seller is not locked after take";
}
