// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes20 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function getDefaultFee(address loanToken, uint256 index) external returns (uint256) envfree;
    function getOfferPrice(uint256 tick) external returns (uint256) envfree;
    function feeSetter() external returns (address) envfree;

    function _.price() external => NONDET;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    // NONDET is sound here: these are external calls (not delegatecalls) that cannot
    // directly write MorphoV2 storage; fee-modifying functions enforce <= MAX_FEE even under reentrancy.
    function _.onBuy(MorphoV2Harness.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(MorphoV2Harness.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.onLiquidate(MorphoV2Harness.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
}

definition MAX_FEE() returns uint256 = 10000000000000000; // 0.01e18 = 1%
definition FEE_STEP() returns uint256 = 1000000000000; // 1e12
definition MAX_FEE_UNITS() returns uint256 = 10000; // MAX_FEE / FEE_STEP
definition WAD() returns mathint = 1000000000000000000;

// Ghost mirrors of the raw uint16 fee storage, updated on every Sstore/Sload.
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

/// Default fees for any loan token are bounded by MAX_FEE.
invariant defaultFeeWithinMaxFee(address loanToken, uint256 index)
    index <= 5 => ghostDefaultFeeUnits[loanToken][index] <= MAX_FEE_UNITS();


/// Every obligation's fee breakpoints are bounded by MAX_FEE.
invariant obligationFeeWithinMaxFee(bytes20 id, uint256 index)
    index <= 5 => ghostObligationFeeUnits[id][index] <= MAX_FEE_UNITS()
    {
        preserved with (env e) {
            require forall address t. forall uint256 i.
                i <= 5 => ghostDefaultFeeUnits[t][i] <= MAX_FEE_UNITS();
        }
    }

/// --- feePct = 0 => fee = 0 and more --- ///

/// tradingFee(id, t) <= MAX_FEE for any time to maturity.
rule tradingFeeAlwaysWithinMaxFee(bytes20 id, uint256 timeToMaturity) {
    requireInvariant obligationFeeWithinMaxFee(id, 0);
    requireInvariant obligationFeeWithinMaxFee(id, 1);
    requireInvariant obligationFeeWithinMaxFee(id, 2);
    requireInvariant obligationFeeWithinMaxFee(id, 3);
    requireInvariant obligationFeeWithinMaxFee(id, 4);
    requireInvariant obligationFeeWithinMaxFee(id, 5);

    assert tradingFee(id, timeToMaturity) <= MAX_FEE();
}

/// Fee linear interpolation never exceeds an upper bound that covers all breakpoints.
rule tradingFeeBoundedByBreakpoints(bytes20 id, uint256 timeToMaturity, uint256 upperBound) {
    require tradingFee(id, 0) <= upperBound;
    require tradingFee(id, 86400) <= upperBound;
    require tradingFee(id, 604800) <= upperBound;
    require tradingFee(id, 2592000) <= upperBound;
    require tradingFee(id, 7776000) <= upperBound;
    require tradingFee(id, 15552000) <= upperBound;

    assert tradingFee(id, timeToMaturity) <= upperBound;
}

/// The interpolation never goes below a lower bound that all breakpoints satisfy.
rule tradingFeeLowerBoundedByBreakpoints(bytes20 id, uint256 timeToMaturity, uint256 lowerBound) {
    require tradingFee(id, 0) >= lowerBound;
    require tradingFee(id, 86400) >= lowerBound;
    require tradingFee(id, 604800) >= lowerBound;
    require tradingFee(id, 2592000) >= lowerBound;
    require tradingFee(id, 7776000) >= lowerBound;
    require tradingFee(id, 15552000) >= lowerBound;

    assert tradingFee(id, timeToMaturity) >= lowerBound;
}

/// If all fee breakpoints are zero, the interpolated fee is zero everywhere.
rule zeroFeesImplyZeroTradingFee(bytes20 id, uint256 timeToMaturity) {
    require tradingFee(id, 0) == 0;
    require tradingFee(id, 86400) == 0;
    require tradingFee(id, 604800) == 0;
    require tradingFee(id, 2592000) == 0;
    require tradingFee(id, 7776000) == 0;
    require tradingFee(id, 15552000) == 0;

    assert tradingFee(id, timeToMaturity) == 0;
}

/// setObligationTradingFee reverts if caller is not feeSetter.
rule setObligationTradingFeeRequiresFeeSetter(env e, bytes20 id, uint256 index, uint256 newFee) {
    setObligationTradingFee(e, id, index, newFee);

    assert e.msg.sender == feeSetter();
}

/// setDefaultTradingFee reverts if caller is not feeSetter.
rule setDefaultTradingFeeRequiresFeeSetter(env e, address loanToken, uint256 index, uint256 newFee) {
    setDefaultTradingFee(e, loanToken, index, newFee);

    assert e.msg.sender == feeSetter();
}

/// Default fee breakpoints can only change via setDefaultTradingFee.
rule defaultFeesOnlyChangeViaSetDefault(env e, method f, address loanToken, uint256 index) {
    require index <= 5;
    uint256 feeBefore = getDefaultFee(loanToken, index);

    calldataarg args;
    f(e, args);

    assert getDefaultFee(loanToken, index) != feeBefore =>
        f.selector == sig:setDefaultTradingFee(address, uint256, uint256).selector;
}




/// buyerAssets >= sellerAssets, and fee bounded by buyer's notional.
rule actualFeeChargedNonNegative(
    env e, uint256 buyerAssets, uint256 sellerAssets,
    uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2Harness.Offer offer, MorphoV2Harness.Signature signature,
    bytes32 root, bytes32[] proof
) {
    require forall bytes20 _id. forall uint256 _i.
        _i <= 5 => ghostObligationFeeUnits[_id][_i] <= MAX_FEE_UNITS();
    require forall address _t. forall uint256 _i.
        _i <= 5 => ghostDefaultFeeUnits[_t][_i] <= MAX_FEE_UNITS();

    uint256 offerPrice = getOfferPrice(offer.tick);

    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut =
        take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    assert buyerAssetsOut >= sellerAssetsOut;

    // fee is bounded by buyer's notional
    uint256 feeRate = computeTradingFeeForOffer(e, offer);
    mathint buyerPrice = offer.buy
        ? to_mathint(offerPrice)
        : to_mathint(offerPrice) + to_mathint(feeRate);

    assert (obligationUnits > 0 && buyerAssets == 0 && sellerAssets == 0 && obligationShares == 0)
    || (obligationShares > 0 && buyerAssets == 0 && sellerAssets == 0 && obligationUnits == 0) =>
    (to_mathint(buyerAssetsOut) - to_mathint(sellerAssetsOut)) * WAD() <= to_mathint(obligationUnitsOut) * buyerPrice;
}

// buyerPrice >= sellerPrice (feeRate <= offerPrice for buy offers)
/// for sell offers buyerPrice >= sellerPrice is trivially true
rule feeRateDoesNotExceedOfferPrice(
    env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2Harness.Offer offer, MorphoV2Harness.Signature signature, bytes32 root, bytes32[] proof
) {
    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut =
        take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    uint256 feeRate = computeTradingFeeForOffer(e, offer);
    uint256 offerPrice = getOfferPrice(offer.tick);

    // For buy offers: sellerPrice = offerPrice − feeRate, so feeRate must not exceed offerPrice
    assert offer.buy => to_mathint(feeRate) <= to_mathint(offerPrice);
}

/// When the non-zero input is obligationUnits, the maker's asset amount is the exact floor of the notional value at the offer price.
/// makerAssets = floor(obligationUnits * offerPrice / WAD).
rule makerAssetsEqualsBondsTimesPrice(
    env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares,
    address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2Harness.Offer offer, MorphoV2Harness.Signature signature, bytes32 root, bytes32[] proof
) {
    require obligationUnits > 0;
    require buyerAssets == 0 && sellerAssets == 0 && obligationShares == 0;

    uint256 offerPrice = getOfferPrice(offer.tick);

    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut =
        take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    mathint makerAssets = offer.buy ? to_mathint(buyerAssetsOut) : to_mathint(sellerAssetsOut);

    // encode floor 
    assert makerAssets * WAD() <= to_mathint(obligationUnitsOut) * to_mathint(offerPrice);
    assert (makerAssets + 1) * WAD() > to_mathint(obligationUnitsOut) * to_mathint(offerPrice);
}

/// During a take with obligationUnits input, the fee charged (buyerAssets − sellerAssets)
/// equals floor(obligationUnits × tradingFeeRate / WAD), possibly +1 due to two separate floors.
rule feeAmountEqualsBondsTimesRate(
    env e, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, address taker,
    address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller,
    MorphoV2Harness.Offer offer, MorphoV2Harness.Signature signature, bytes32 root, bytes32[] proof
) {
    require obligationUnits > 0;
    require buyerAssets == 0 && sellerAssets == 0 && obligationShares == 0;

    uint256 buyerAssetsOut;
    uint256 sellerAssetsOut;
    uint256 obligationUnitsOut;
    uint256 obligationSharesOut;

    buyerAssetsOut, sellerAssetsOut, obligationUnitsOut, obligationSharesOut =
        take(e, buyerAssets, sellerAssets, obligationUnits, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);

    uint256 feeRate = computeTradingFeeForOffer(e, offer);

    mathint feeAmount = to_mathint(buyerAssetsOut) - to_mathint(sellerAssetsOut);
    mathint oUxFee = to_mathint(obligationUnitsOut) * to_mathint(feeRate);

    // feeAmount >= floor(oU * feeRate / WAD)
    assert (feeAmount + 1) * WAD() > oUxFee;

    // feeAmount <= floor(oU * feeRate / WAD) + 1
    assert (feeAmount - 1) * WAD() <= oUxFee;
}
