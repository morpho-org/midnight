// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function claimableTradingFee(address token) external returns (uint256) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function Midnight.obligationCreated(bytes32 id) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory, uint256) internal returns (address) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;

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

/// HELPERS ///

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition MAX_TTM() returns mathint = 100 * 365 * 86400;

function summaryToId(Midnight.Obligation obligation) returns (bytes32) {
    return Utils.hashObligation(obligation);
}

function obligationIsCreated(Midnight.Obligation obligation) returns (bool) {
    return Midnight.obligationCreated(summaryToId(obligation));
}

persistent ghost mapping(bytes32 => mathint) sumDebt {
    init_state axiom (forall bytes32 id. sumDebt[id] == 0);
}

hook Sstore position[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebt[id] = sumDebt[id] - to_mathint(oldDebt) + to_mathint(newDebt);
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 r;
    require x == 0 => r == 0;
    require d > 0 && y <= d => r <= x;
    require d > 0 && x <= d && y <= d => x - r <= d - y;
    return r;
}

rule takeInputOutputConsistency(env e, uint256 unitsInput, address taker, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 unitsOutput;

    uint256 claimableBefore = claimableTradingFee(offer.obligation.loanToken);

    buyerAssetsOutput, sellerAssetsOutput, unitsOutput = take(e, unitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, ratifierData, root, proof);

    // The output units is equal to the input.
    assert unitsOutput == unitsInput;

    // If the input is zero, all the output arguments are zero.
    assert unitsInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && unitsOutput == 0;

    // The claimable trading fee increases by exactly the spread.
    assert claimableTradingFee(offer.obligation.loanToken) == claimableBefore + buyerAssetsOutput - sellerAssetsOutput;
}

rule liquidateInputOutputConsistency(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    uint256 seizedAssetsOutput;
    uint256 repaidUnitsOutput;

    seizedAssetsOutput, repaidUnitsOutput = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    // At most one of the input arguments can be zero.
    assert seizedAssets == 0 || repaidUnits == 0;

    // The output arguments are equal to the input arguments if the input arguments are non-zero.
    assert seizedAssets == 0 || seizedAssetsOutput == seizedAssets;
    assert repaidUnits == 0 || repaidUnitsOutput == repaidUnits;

    // If all the input arguments are zero, all the output arguments are zero.
    assert repaidUnits == 0 && seizedAssets == 0 => seizedAssetsOutput == 0 && repaidUnitsOutput == 0;
}

rule obligationLossFactorMonotonicallyIncreases(bytes32 id, method f, env e, calldataarg args) {
    uint128 lossFactorBefore = currentContract.obligationState[id].lossFactor;
    f(e, args);
    uint128 lossFactorAfter = currentContract.obligationState[id].lossFactor;
    assert lossFactorAfter >= lossFactorBefore;
}

rule lastLossFactorMonotonicallyIncreases(bytes32 id, address user, method f, env e, calldataarg args) {
    requireInvariant lastLossFactorLeqObligationLossFactor(id, user);
    uint128 lastLossFactorBefore = lastLossFactor(id, user);
    f(e, args);
    uint128 lastLossFactorAfter = lastLossFactor(id, user);
    assert lastLossFactorAfter >= lastLossFactorBefore;
}

rule creditAndDebtCannotIncreaseWhenLossFactorIsMaxed(bytes32 id, address user, method f, env e, calldataarg args) {
    require currentContract.obligationState[id].lossFactor == max_uint128, "assume loss factor is maxed out";
    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);

    f(e, args);

    assert creditOf(id, user) <= creditBefore;
    assert debtOf(id, user) <= debtBefore;
}

/// INVARIANTS ///

strong invariant totalUnitsEqualsSumNegativeDebtPlusWithdrawable(bytes32 id)
    to_mathint(totalUnits(id)) == sumDebt[id] + to_mathint(withdrawable(id));

strong invariant defaultContinuousFeeBoundedAll()
    forall address token. currentContract.defaultContinuousFee[token] <= MAX_CONTINUOUS_FEE();

strong invariant continuousFeeBounded(bytes32 id)
    currentContract.obligationState[id].continuousFee <= MAX_CONTINUOUS_FEE()
    {
        preserved with (env e) {
            requireInvariant defaultContinuousFeeBoundedAll();
        }
    }

strong invariant pendingContinuousFeeBoundedByCredit(bytes32 id, address user)
    pendingFee(id, user) <= creditOf(id, user)
    {
        preserved with (env e) {
            requireInvariant continuousFeeBounded(id);
            requireInvariant defaultContinuousFeeBoundedAll();
        }
        preserved take(uint256 unitsInput, address taker, address takerCallbackAddress, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) with (env e) {
            requireInvariant continuousFeeBounded(id);
            requireInvariant defaultContinuousFeeBoundedAll();
            require to_mathint(offer.obligation.maturity) <= to_mathint(e.block.timestamp) + MAX_TTM(); // TODO verify this cleanly
        }
    }

rule noRemainingContinuousFeeWithoutCredit(bytes32 id, address user) {
    requireInvariant pendingContinuousFeeBoundedByCredit(id, user);
    assert creditOf(id, user) == 0 => pendingFee(id, user) == 0;
}

strong invariant lastLossFactorLeqObligationLossFactor(bytes32 id, address user)
    lastLossFactor(id, user) <= currentContract.obligationState[id].lossFactor;

/// A user cannot have both credit and debt.
strong invariant noCreditAndDebt(bytes32 id, address user)
    creditOf(id, user) == 0 || debtOf(id, user) == 0;
