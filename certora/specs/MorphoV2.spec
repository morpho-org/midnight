// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address owner) external returns (uint256) envfree;
    function debtOf(bytes32 id, address owner) external returns (uint256) envfree;

    function _.price() external => NONDET;
    function _.toId(MorphoV2.Obligation memory obligation, uint256 chainId, address morphoV2) internal => NONDET;
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

hook Sstore debtOf[KEY bytes32 id][KEY address owner] uint256 newDebt (uint256 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

rule takeInputOutputConsistency(env e, uint256 takerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;
    uint256 expectedBuyerAssets = offer.buy ? 0 : takerAssets;
    uint256 expectedSellerAssets = offer.buy ? takerAssets : 0;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, takerAssets, obligationUnits, obligationShares, taker, offer, signature, root, proof, takerCallbackAddress, takerCallbackData);

    assert expectedBuyerAssets == 0 || buyerAssetsOutput == expectedBuyerAssets;
    assert expectedSellerAssets == 0 || sellerAssetsOutput == expectedSellerAssets;
    assert obligationUnits == 0 || obligationUnitsOutput == obligationUnits;
    assert obligationShares == 0 || obligationSharesOutput == obligationShares;
}

rule offerInputsConsumed(env e, uint256 takerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, takerAssets, obligationUnits, obligationShares, taker, offer, signature, root, proof, takerCallbackAddress, takerCallbackData);

    assert offer.assets == 0 || consumed(offer.maker, offer.group) == consumedBefore + (offer.buy ? buyerAssetsOutput : sellerAssetsOutput);
    assert offer.obligationUnits == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsOutput;
    assert offer.obligationShares == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationSharesOutput;
}

rule offerInputsLimit(env e, uint256 takerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, takerAssets, obligationUnits, obligationShares, taker, offer, signature, root, proof, takerCallbackAddress, takerCallbackData);

    assert offer.assets == 0 || (offer.buy ? buyerAssetsOutput : sellerAssetsOutput) <= offer.assets - consumedBefore;
    assert offer.obligationUnits == 0 || obligationUnitsOutput <= offer.obligationUnits - consumedBefore;
    assert offer.obligationShares == 0 || obligationSharesOutput <= offer.obligationShares - consumedBefore;
}

/// INVARIANTS ///

strong invariant notBorrowerAndLender(bytes32 id, address user)
    sharesOf(id, user) == 0 || debtOf(id, user) == 0;

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes32 id)
    totalShares(id) == sumSharesOf[id];
