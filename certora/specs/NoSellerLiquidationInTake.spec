// SPDX-License-Identifier: GPL-2.0-or-later

using Havoc as callback;
using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;
    function _.canLiquidate(address) external => NONDET;
    function liquidate(Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external returns (uint256, uint256) with(env e) => wrappedLiquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;

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

persistent ghost bool liquidated;

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function wrappedLiquidate(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) returns (uint256, uint256) {
    uint256 seizedAssetsOut;
    uint256 repaidUnitsOut;
    seizedAssetsOut, repaidUnitsOut = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    if (summaryToId(obligation) == globalId && borrower == globalBorrower) {
        liquidated = true;
    }
    return (seizedAssetsOut, repaidUnitsOut);
}

function genericCallback() {
    address dummy;
    env e;
    assert liquidationLocked(e, globalId, globalBorrower), "take callbacks begin with seller lock on";

    callback.callHavoc(e, dummy);

    require liquidationLocked(e, globalId, globalBorrower), "lock preserved by callback";
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

// Together the 2 rules below show that the seller cannot be liquidated inside a take callback.
rule liquidationLockInTakeCallbacks(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    globalId = summaryToId(offer.obligation);
    globalBorrower = offer.buy ? taker : offer.maker;
    require liquidationLocked(e, globalId, globalBorrower), "borrower is locked before call";

    liquidated = false;

    take(e, units, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    assert true;
}

rule sellerCannotBeLiquidatedAndLockCannotBeRemovedUnderLiquidationLock(method f, env e, calldataarg args, bytes32 id, address borrower) filtered { f -> !f.isView } {
    globalId = id;
    globalBorrower = borrower;
    require liquidationLocked(e, globalId, globalBorrower), "borrower is locked before call";

    liquidated = false;

    f(e, args);

    assert !liquidated, "locked borrower not liquidated";
    assert liquidationLocked(e, globalId, globalBorrower), "lock is not removed under liquidation lock";
}
