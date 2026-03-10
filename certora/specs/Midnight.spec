// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address owner) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function remainingContinuousFee(bytes32 id, address user) external returns (uint128) envfree;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

persistent ghost mapping(bytes32 => mathint) sumSharesOf {
    init_state axiom (forall bytes32 id. sumSharesOf[id] == 0);
}

hook Sstore sharesOf[KEY bytes32 id][KEY address owner] uint256 newShares (uint256 oldShares) {
    sumSharesOf[id] = sumSharesOf[id] - oldShares + newShares;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}

hook Sstore borrowerState[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    return res;
}

rule takeInputOutputConsistency(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    // The output obligationShares is equal to the input.
    assert obligationSharesOutput == obligationSharesInput;

    // If the input is zero, all the output arguments are zero.
    assert obligationSharesInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0 && obligationUnitsOutput == 0 && obligationSharesOutput == 0;
}

rule offerInputsConsumed(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    if (offer.obligationUnits > 0) {
        assert consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsOutput;
    } else {
        assert consumed(offer.maker, offer.group) == consumedBefore + obligationSharesOutput;
    }
}

rule offerInputsLimit(env e, uint256 obligationSharesInput, address taker, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    take(e, obligationSharesInput, taker, takerCallbackAddress, takerCallbackData, receiver, offer, signature, root, proof);

    if (offer.obligationUnits > 0) {
        assert consumed(offer.maker, offer.group) <= offer.obligationUnits;
    } else {
        assert consumed(offer.maker, offer.group) <= offer.obligationShares;
    }
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

/// INVARIANTS ///

strong invariant notBorrowerAndLender(bytes32 id, address user)
    sharesOf(id, user) == 0 || debtOf(id, user) == 0;

strong invariant noRemainingContinuousFeeWithoutDebt(bytes32 id, address user)
    debtOf(id, user) == 0 => remainingContinuousFee(id, user) == 0;

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes32 id)
    totalShares(id) == sumSharesOf[id];
