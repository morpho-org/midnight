// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as Midnight;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function Midnight.obligationCreated(bytes32 id) external returns (bool) envfree;
    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;

    // Tokens are assumed to not reenter.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

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

rule takeInputOutputConsistency(env e, uint256 unitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 unitsOutput;

    buyerAssetsOutput, sellerAssetsOutput, unitsOutput = take(e, unitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    // The output units is equal to the input.
    assert unitsOutput == unitsInput;

    // If the input is zero, all the output arguments are zero.
    assert unitsInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && unitsOutput == 0;
}

rule offerInputsConsumed(env e, uint256 unitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, unitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert consumed(offer.maker, offer.group) == consumedBefore + unitsInput;
}

rule offerInputsLimit(env e, uint256 unitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, unitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert unitsInput <= offer.maxUnits - consumedBefore;
}

rule liquidateInputOutputConsistency(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    uint256 seizedAssetsOutput;
    uint256 repaidUnitsOutput;

    seizedAssetsOutput, repaidUnitsOutput = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // At most one of the input arguments can be zero.
    assert seizedAssets == 0 || repaidUnits == 0;

    // The output arguments are equal to the input arguments if the input arguments are non-zero.
    assert seizedAssets == 0 || seizedAssetsOutput == seizedAssets;
    assert repaidUnits == 0 || repaidUnitsOutput == repaidUnits;

    // If all the input arguments are zero, all the output arguments are zero.
    assert repaidUnits == 0 && seizedAssets == 0 => seizedAssetsOutput == 0 && repaidUnitsOutput == 0;
}

rule obligationLossIndexMonotonicallyIncreases(bytes32 id, method f, env e, calldataarg args) {
    uint128 lossIndexBefore = currentContract.obligationState[id].lossIndex;
    f(e, args);
    uint128 lossIndexAfter = currentContract.obligationState[id].lossIndex;
    assert lossIndexAfter >= lossIndexBefore;
}

rule userLossIndexMonotonicallyIncreases(bytes32 id, address user, method f, env e, calldataarg args) {
    requireInvariant userLossIndexLeqObligationLossIndex(id, user);
    uint128 lossIndexBefore = userLossIndex(id, user);
    f(e, args);
    uint128 lossIndexAfter = userLossIndex(id, user);
    assert lossIndexAfter >= lossIndexBefore;
}

/// INVARIANTS ///

strong invariant totalUnitsEqualsSumNegativeDebtPlusWithdrawable(bytes32 id)
    to_mathint(totalUnits(id)) == sumDebt[id] + to_mathint(withdrawable(id));

strong invariant pendingContinuousFeeBoundedByCredit(bytes32 id, address user)
    pendingFee(id, user) <= creditOf(id, user);

rule noRemainingContinuousFeeWithoutCredit(bytes32 id, address user) {
    requireInvariant pendingContinuousFeeBoundedByCredit(id, user);
    assert creditOf(id, user) == 0 => pendingFee(id, user) == 0;
}

strong invariant userLossIndexLeqObligationLossIndex(bytes32 id, address user)
    userLossIndex(id, user) <= currentContract.obligationState[id].lossIndex;

/// A user cannot have both credit and debt, excluding PASSIVE_FEE_RECIPIENT who receives
/// credit from fee accrual and could theoretically be a trade participant.
strong invariant noCreditAndDebt(bytes32 id, address user)
    user != Utils.passiveFeeRecipient() => (creditOf(id, user) == 0 || debtOf(id, user) == 0);
