// SPDX-License-Identifier: GPL-2.0-or-later
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function authorized(address user, address someone) external returns (bool) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(address owner, bytes32 id) external returns (uint256) envfree;
    function debtOf(address owner, bytes32 id) external returns (uint256) envfree;
    function _.price() external => NONDET;
}

/// HELPERS ///
persistent ghost mapping(bytes32 => mathint) sumSharesOf {
    init_state axiom (forall bytes32 id. sumSharesOf[id] == 0);
}

hook Sstore sharesOf[KEY address owner][KEY bytes32 id] uint256 newShares (uint256 oldShares) {
    sumSharesOf[id] = sumSharesOf[id] - oldShares + newShares;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}

hook Sstore debtOf[KEY address owner][KEY bytes32 id] uint256 newDebt (uint256 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

rule takeInputOutputConsistency(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Proof proof, MorphoV2.Signature signature, address takerCallback, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, proof, signature, takerCallback, takerCallbackData);

    assert buyerAssets == 0 || buyerAssetsOutput == buyerAssets;
    assert sellerAssets == 0 || sellerAssetsOutput == sellerAssets;
    assert obligationUnits == 0 || obligationUnitsOutput == obligationUnits;
    assert obligationShares == 0 || obligationSharesOutput == obligationShares;
}

rule offerInputsConsumed(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Proof proof, MorphoV2.Signature signature, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, proof, signature, takerCallbackAddress, takerCallbackData);

    assert offer.assets == 0 || consumed(offer.maker, offer.group) == consumedBefore + (offer.buy ? buyerAssetsOutput : sellerAssetsOutput);
    assert offer.obligationUnits == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationUnitsOutput;
    assert offer.obligationShares == 0 || consumed(offer.maker, offer.group) == consumedBefore + obligationSharesOutput;
}

rule offerInputsLimit(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Proof proof, MorphoV2.Signature signature, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 consumedBefore = consumed(offer.maker, offer.group);

    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, proof, signature, takerCallbackAddress, takerCallbackData);

    assert offer.assets == 0 || (offer.buy ? buyerAssetsOutput : sellerAssetsOutput) <= offer.assets - consumedBefore;
    assert offer.obligationUnits == 0 || obligationUnitsOutput <= offer.obligationUnits - consumedBefore;
    assert offer.obligationShares == 0 || obligationSharesOutput <= offer.obligationShares - consumedBefore;
}

/// INVARIANTS ///
strong invariant notBorrowerAndLender(bytes32 id, address user)
    sharesOf(user, id) == 0 || debtOf(user, id) == 0;

strong invariant totalUnitsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalUnits(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumSharesOf(bytes32 id)
    totalShares(id) == sumSharesOf[id];

strong invariant sharePriceBelowOne(bytes32 id)
    totalShares(id) >= totalUnits(id);

rule onlyUserCanAuthorizeWithoutSig(env e, method f, calldataarg data)
filtered { f -> !f.isView && f.selector != sig:setAuthorizedWithSig(MorphoV2.Authorization memory, MorphoV2.Signature calldata).selector } {
    address user;
    address someone;

    require user != e.msg.sender;

    bool authorizedBefore = authorized(user, someone);

    f(e, data);

    bool authorizedAfter = authorized(user, someone);

    assert authorizedAfter == authorizedBefore;
}

rule onlyUserOrAuthorizedCanRatify(env e, address onBehalf, bytes32 root, bool newIsRatified) {
    setRatified@withrevert(e, onBehalf, root, newIsRatified);
    assert !lastReverted => (onBehalf == e.msg.sender || authorized(onBehalf, e.msg.sender));
}

rule unauthorizedTakeFails(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Proof proof, MorphoV2.Signature signature, address takerCallbackAddress, bytes takerCallbackData) {
    take@withrevert(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, proof, signature, takerCallbackAddress, takerCallbackData);
    assert !lastReverted => e.msg.sender == taker || authorized(taker, e.msg.sender);
}

rule unauthorizedOnRatifyFails(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Proof proof, MorphoV2.Signature signature, address takerCallbackAddress, bytes takerCallbackData) {
    require signature.v != 0, "no ratification callback without a signature";
    require offer.ratifier != 0, "no ratification callback without a ratifier";
    take@withrevert(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, proof, signature, takerCallbackAddress, takerCallbackData);
    assert !lastReverted => offer.maker == offer.ratifier || authorized(offer.maker, offer.ratifier);
}

rule unauthorizedWithdrawCollateralFails(env e, MorphoV2.Obligation obligation, address collateral, uint256 assets, address onBehalf) {
    withdrawCollateral@withrevert(e, obligation, collateral, assets, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || authorized(onBehalf, e.msg.sender);
}

rule unauthorizedWithdrawFails(env e, MorphoV2.Obligation obligation, uint256 obligationUnits, uint256 shares, address onBehalf) {
    withdraw@withrevert(e, obligation, obligationUnits, shares, onBehalf);
    assert !lastReverted => e.msg.sender == onBehalf || authorized(onBehalf, e.msg.sender);
}
