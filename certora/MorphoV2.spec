// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    
    function withdrawable(bytes32 id) external returns uint256 envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
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

rule takeInputOutputConsistency(env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker, MorphoV2.Offer offer, MorphoV2.Signature signature, bytes32 root, bytes32[] proof, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;
    uint256 obligationUnitsOutput;
    uint256 obligationSharesOutput;

    buyerAssetsOutput, sellerAssetsOutput, obligationUnitsOutput, obligationSharesOutput = take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, offer, signature, root, proof, takerCallbackAddress, takerCallbackData);

    assert buyerAssets == 0 || buyerAssetsOutput == buyerAssets;
    assert sellerAssets == 0 || sellerAssetsOutput == sellerAssets;
    assert obligationUnits == 0 || obligationUnitsOutput == obligationUnits;
    assert obligationShares == 0 || obligationSharesOutput == obligationShares;
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
