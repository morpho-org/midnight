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
    function FlashTakeCallback.startFlashloan(bytes32 obligationId, uint256 units) internal => CVL_flashLoanStart(obligationId, units);
    function FlashTakeCallback.endFlashloan(bytes32 obligationId, uint256 units) internal => CVL_flashLoanEnd(obligationId, units);
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

// Tracks the transient flashloaned units during callbacks.
// We use persistent ghost to ensure these values are not changed by the callback.
// This is sound as we prove the rule flashloanedUnitsPaidBack which ensures that the flashloaned units after the callback are the same as before.
persistent ghost mapping(bytes32 => mathint) flashloanedUnits {
    init_state axiom (forall bytes32 id. flashloanedUnits[id] == 0);
}

hook Sstore position[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebt[id] = sumDebt[id] - to_mathint(oldDebt) + to_mathint(newDebt);
}

function CVL_flashLoanStart(bytes32 id, uint256 units) {
    flashloanedUnits[id] = flashloanedUnits[id] + units;
}

function CVL_flashLoanEnd(bytes32 id, uint256 units) {
    flashloanedUnits[id] = flashloanedUnits[id] - units;
}

// For any token, the flash loaned units before and after a call is the same.
// This rule is useful to prove that using persistent ghost for the flashloaned units mapping is sound.
rule flashloanedUnitsPaidBack(method f, bytes32 id) {
    env e;
    calldataarg args;
    mathint oldFlashloanedUnits = flashloanedUnits[id];
    f(e, args);
    assert flashloanedUnits[id] == oldFlashloanedUnits, "flashloaned units paid back";
}

strong invariant totalUnitsEqualsSumDebtPlusWithdrawablePlusGap(bytes32 id)
    to_mathint(totalUnits(id)) == sumDebt[id] + to_mathint(withdrawable(id)) + flashloanedUnits[id]
    {
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) with (env e) {
            require e.block.timestamp >= 0;
            require e.block.timestamp < 2 ^ 128;
            require userLossIndex(id, offer.maker) <= lossIndex(id);
            require userLossIndex(id, taker) <= lossIndex(id);
        }
    }

weak invariant flashloanedUnitsZero(bytes32 id)
    flashloanedUnits[id] == 0;
