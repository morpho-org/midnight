// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes20 id) external returns (uint256) envfree;
    function totalUnits(bytes20 id) external returns (uint256) envfree;
    function totalShares(bytes20 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes20 id, address owner) external returns (uint256) envfree;
    function debtOf(bytes20 id, address user) external returns (uint256) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(MorphoV2.Obligation memory, uint256, address) internal returns (bytes20) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

persistent ghost mapping(bytes20 => mathint) sumSharesOf {
    init_state axiom (forall bytes20 id. sumSharesOf[id] == 0);
}

hook Sstore sharesOf[KEY bytes20 id][KEY address owner] uint256 newShares (uint256 oldShares) {
    sumSharesOf[id] = sumSharesOf[id] - oldShares + newShares;
}

persistent ghost mapping(bytes20 => mathint) sumDebtOf {
    init_state axiom (forall bytes20 id. sumDebtOf[id] == 0);
}

hook Sstore borrowerState[KEY bytes20 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    uint256 res;
    return res;
}

rule takeInputOutputConsistency(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, address receiver, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    // At most one of the input arguments can be zero.
    mathint buyerAssetsIsNonZero = buyerAssets > 0 ? 1 : 0;
    mathint sellerAssetsIsNonZero = sellerAssets > 0 ? 1 : 0;
    mathint obligationUnitsIsNonZero = obligationUnits > 0 ? 1 : 0;
    mathint obligationSharesIsNonZero = obligationShares > 0 ? 1 : 0;
    assert buyerAssetsIsNonZero + sellerAssetsIsNonZero + obligationUnitsIsNonZero + obligationSharesIsNonZero <= 1;

    // The output arguments are equal to the input arguments if the input arguments are non-zero.
    assert buyerAssets == 0 || buyerAssetsOutput == buyerAssets;
    assert sellerAssets == 0 || sellerAssetsOutput == sellerAssets;
    assert obligationUnits == 0 || obligationUnitsOutput == obligationUnits;
    assert obligationShares == 0 || obligationSharesOutput == obligationShares;

    // If all the input arguments are zero, all the output arguments are zero.
    assert buyerAssets == 0 && sellerAssets == 0 && obligationUnits == 0 && obligationShares == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && obligationUnitsOutput == 0 && obligationSharesOutput == 0;
}

rule offerInputsConsumed(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, address receiver, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert offer.assets == 0 || consumed(offer.maker, offer.group) == consumedBefore + (offer.buy ? buyerAssetsOutput : sellerAssetsOutput);
    assert offer.obligationUnits == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsOutput;
    assert offer.obligationShares == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationSharesOutput;
}

rule offerInputsLimit(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, address receiver, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    assert offer.assets == 0 || (offer.buy ? buyerAssetsOutput : sellerAssetsOutput) <= offer.assets - consumedBefore;
    assert offer.obligationUnits == 0 || obligationUnitsOutput <= offer.obligationUnits - consumedBefore;
    assert offer.obligationShares == 0 || obligationSharesOutput <= offer.obligationShares - consumedBefore;
}

rule liquidateInputOutputConsistency(env e, MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
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

/// INVARIANTS ///

strong invariant notBorrowerAndLender(bytes20 id, address user)
    sharesOf(id, user) == 0 || debtOf(id, user) == 0;

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes20 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes20 id)
    totalShares(id) == sumSharesOf[id];
