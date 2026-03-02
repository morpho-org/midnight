// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
}

definition MAX_FEE_UNITS() returns uint256 = 5000; 

ghost mapping(bytes20 => mapping(uint256 => mathint)) ghostObligationFeeUnits {
    init_state axiom forall bytes20 id. forall uint256 i. ghostObligationFeeUnits[id][i] == 0;
}
ghost mapping(address => mapping(uint256 => mathint)) ghostDefaultFeeUnits {
    init_state axiom forall address t. forall uint256 i. ghostDefaultFeeUnits[t][i] == 0;
}

hook Sstore obligationState[KEY bytes20 id].fees[INDEX uint256 idx] uint16 newVal {
    ghostObligationFeeUnits[id][idx] = to_mathint(newVal);
}
hook Sload uint16 val obligationState[KEY bytes20 id].fees[INDEX uint256 idx] {
    require ghostObligationFeeUnits[id][idx] == to_mathint(val);
}

hook Sstore defaultFees[KEY address token][INDEX uint256 idx] uint16 newVal {
    ghostDefaultFeeUnits[token][idx] = to_mathint(newVal);
}
hook Sload uint16 val defaultFees[KEY address token][INDEX uint256 idx] {
    require ghostDefaultFeeUnits[token][idx] == to_mathint(val);
}

/// buyerAssets >= sellerAssets.
rule buyerAssetsGeSellerAssets(
    env e,
    uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares,
    address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    Midnight.Offer offer, Midnight.Signature signature,
    bytes32 root, bytes32[] proof
) {

    // start from a satisfactory state 
    require forall bytes20 _id. forall uint256 _i.
        _i <= 6 => ghostObligationFeeUnits[_id][_i] <= MAX_FEE_UNITS();
    require forall address _t. forall uint256 _i.
        _i <= 6 => ghostDefaultFeeUnits[_t][_i] <= MAX_FEE_UNITS();

    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut =
        take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares,
            taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller,
            offer, signature, root, proof);

    assert buyerAssetsOut >= sellerAssetsOut;
}
