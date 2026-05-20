// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function claimableTradingFee(address token) external returns (uint256) envfree;
    function continuousFeeCredit(bytes32 id) external returns (uint256) envfree;

    // Summarize internals irrelevant to fee-recipient accounting.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address[], uint256[], bytes) external => NONDET;
    function SafeTransferLib.safeTransfer(address token, address receiver, uint256 amount) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address token, address from, address to, uint256 amount) internal => NONDET;
}

/// CLAIMABLE TRADING FEE ///

/// claimableTradingFee is non-decreasing except via claimTradingFee.
rule claimableTradingFeeNonDecreasing(method f, env e, calldataarg args, address token) filtered { f -> !f.isView && f.selector != sig:claimTradingFee(address, uint256, address).selector } {
    uint256 before = claimableTradingFee(token);
    f(e, args);
    assert claimableTradingFee(token) >= before;
}

/// take increases claimableTradingFee[offer.market.loanToken] by exactly buyerAssets - sellerAssets, and does not change claimableTradingFee for any other token.
rule takeIncreasesClaimableTradingFee(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, address anyToken) {
    uint256 before = claimableTradingFee(anyToken);
    uint256 buyerAssets;
    uint256 sellerAssets;
    buyerAssets, sellerAssets, _ = take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);
    assert anyToken == offer.market.loanToken => claimableTradingFee(anyToken) == before + buyerAssets - sellerAssets;
    assert anyToken != offer.market.loanToken => claimableTradingFee(anyToken) == before;
}

/// CONTINUOUS FEE CREDIT ///

/// continuousFeeCredit[id] is non-decreasing except via claimContinuousFee or liquidate
/// (liquidate slashes continuousFeeCredit proportionally when bad debt is realized — see SLASHING).
rule continuousFeeCreditNonDecreasing(method f, env e, calldataarg args, bytes32 id) filtered { f -> !f.isView && f.selector != sig:claimContinuousFee(Midnight.Market, uint256, address).selector && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector } {
    uint256 before = continuousFeeCredit(id);
    f(e, args);
    assert continuousFeeCredit(id) >= before;
}

/// claimContinuousFee decreases continuousFeeCredit[id] by exactly amount,
/// and does not change continuousFeeCredit for any other id.
rule claimContinuousFeeDecreasesByAmount(env e, Midnight.Market market, uint256 amount, address receiver, bytes32 anyId) {
    bytes32 id = toId(e, market);
    uint256 before = continuousFeeCredit(anyId);
    claimContinuousFee(e, market, amount, receiver);
    assert anyId == id => continuousFeeCredit(anyId) == before - amount;
    assert anyId != id => continuousFeeCredit(anyId) == before;
}

/// updatePosition increases continuousFeeCredit[id] by exactly the accruedFee returned by updatePositionView,
/// and does not change continuousFeeCredit for any other id.
rule updatePositionAccruesViewFee(env e, Midnight.Market market, address user, bytes32 anyId) {
    bytes32 id = toId(e, market);
    uint128 accruedFee;
    _, _, accruedFee = updatePositionView(e, market, id, user);
    uint256 before = continuousFeeCredit(anyId);
    updatePosition(e, market, user);
    assert anyId == id => continuousFeeCredit(anyId) == before + accruedFee;
    assert anyId != id => continuousFeeCredit(anyId) == before;
}
