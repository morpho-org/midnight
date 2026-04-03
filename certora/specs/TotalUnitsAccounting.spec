// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function lossIndex(bytes32 id) external returns (uint128) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
    function _.onBuy(bytes32 obligationId, Midnight.Obligation obligation, address buyer, uint256 buyerAssets, uint256 units, bytes data) external => DISPATCHER(true);
    function _.onSell(bytes32 obligationId, Midnight.Obligation obligation, address seller, uint256 sellerAssets, uint256 units, bytes data) external => DISPATCHER(true);
    function DeferredDebtTakeCallback.startDeferredDebt(bytes32 obligationId, uint256 units) internal => CVL_deferredDebtStart(obligationId, units);
    function DeferredDebtTakeCallback.endDeferredDebt(bytes32 obligationId, uint256 units) internal => CVL_deferredDebtEnd(obligationId, units);
    function _.canIncreaseCredit(address) external => NONDET;
    function _.canIncreaseDebt(address) external => NONDET;

    // Tokens are assumed to not reenter.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 r;
    require x == 0 => r == 0;
    require d > 0 && y <= d => r <= x;
    require d > 0 && x <= d && y <= d => x - r <= d - y;
    return r;
}

persistent ghost mapping(bytes32 => mathint) sumDebt {
    init_state axiom (forall bytes32 id. sumDebt[id] == 0);
}

// Tracks the latest credit decrease in each obligation.
// Under the reordered take logic, before both callbacks this stores
// `sellerCreditDecrease`, so `units - latestCreditDecrease[id]` is the
// exact debt increase deferred until after the callbacks.
persistent ghost mapping(bytes32 => mathint) latestCreditDecrease {
    init_state axiom (forall bytes32 id. latestCreditDecrease[id] == 0);
}

// Tracks the transient deferred debt during callbacks.
// We use persistent ghosts to ensure these values are not changed by the callback.
persistent ghost mapping(bytes32 => mathint) deferredDebt {
    init_state axiom (forall bytes32 id. deferredDebt[id] == 0);
}

hook Sstore position[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebt[id] = sumDebt[id] - to_mathint(oldDebt) + to_mathint(newDebt);
}

hook Sstore position[KEY bytes32 id][KEY address owner].credit uint128 newCredit (uint128 oldCredit) {
    if (newCredit < oldCredit) {
        latestCreditDecrease[id] = to_mathint(oldCredit) - to_mathint(newCredit);
    } else {
        latestCreditDecrease[id] = 0;
    }
}

function CVL_deferredDebtStart(bytes32 id, uint256 units) {
    deferredDebt[id] = deferredDebt[id] + units - latestCreditDecrease[id];
}

function CVL_deferredDebtEnd(bytes32 id, uint256 units) {
    deferredDebt[id] = deferredDebt[id] - units + latestCreditDecrease[id];
}

rule deferredDebtPaidBack(method f, bytes32 id) {
    env e;
    calldataarg args;
    mathint oldDeferredDebt = deferredDebt[id];
    f(e, args);
    assert deferredDebt[id] == oldDeferredDebt, "deferred debt paid back";
}

strong invariant totalUnitsEqualsSumDebtPlusWithdrawablePlusDeferredDebt(bytes32 id)
    to_mathint(totalUnits(id)) == sumDebt[id] + withdrawable(id) + deferredDebt[id]
    {
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) with (env e) {
            require e.block.timestamp >= 0;
            require e.block.timestamp < 2 ^ 128;
            require userLossIndex(id, offer.maker) <= lossIndex(id);
            require userLossIndex(id, taker) <= lossIndex(id);
        }
    }

weak invariant deferredDebtZero(bytes32 id)
    deferredDebt[id] == 0;
