// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function balanceOf(bytes32 id, address user) external returns (int256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

persistent ghost mapping(bytes32 => mathint) sumBalanceOf {
    init_state axiom (forall bytes32 id. sumBalanceOf[id] == 0);
}

persistent ghost mapping(bytes32 => mathint) sumPositiveBalanceOf {
    init_state axiom (forall bytes32 id. sumPositiveBalanceOf[id] == 0);
}

persistent ghost mapping(bytes32 => mathint) sumNegativeBalanceOf {
    init_state axiom (forall bytes32 id. sumNegativeBalanceOf[id] == 0);
}

function negativePart(mathint x) returns mathint {
    return x < 0 ? -x : 0;
}

function positivePart(mathint x) returns mathint {
    return x > 0 ? x : 0;
}

hook Sstore position[KEY bytes32 id][KEY address owner].balance int256 newBalance (int256 oldBalance) {
    sumBalanceOf[id] = sumBalanceOf[id] - oldBalance + newBalance;
    sumPositiveBalanceOf[id] = sumPositiveBalanceOf[id] - positivePart(to_mathint(oldBalance)) + positivePart(to_mathint(newBalance));
    sumNegativeBalanceOf[id] = sumNegativeBalanceOf[id] - negativePart(to_mathint(oldBalance)) + negativePart(to_mathint(newBalance));
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    uint256 res;
    require y > d || res <= x;
    return res;
}

rule takeInputOutputConsistency(env e, uint256 obligationUnitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput = take(e, obligationUnitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    // The output obligationUnits is equal to the input.
    assert obligationUnitsOutput == obligationUnitsInput;

    // If the input is zero, all the output arguments are zero.
    assert obligationUnitsInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && obligationUnitsOutput == 0;
}

rule offerInputsConsumed(env e, uint256 obligationUnitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, obligationUnitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsInput;
}

rule offerInputsLimit(env e, uint256 obligationUnitsInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    take(e, obligationUnitsInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert obligationUnitsInput <= offer.obligationUnits - consumedBefore;
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

strong invariant totalUnitsEqualsSumNegativeBalancePlusWithdrawable(bytes32 id)
    to_mathint(totalUnits(id)) == sumNegativeBalanceOf[id] + to_mathint(withdrawable(id));

strong invariant userLossIndexLeqObligationLossIndex(bytes32 id, address user)
    userLossIndex(id, user) <= currentContract.obligationState[id].lossIndex;
