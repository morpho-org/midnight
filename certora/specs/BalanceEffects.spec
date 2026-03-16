// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function balanceOf(bytes32 id, address user) external returns (int256) envfree;
    function balanceOfAfterSlashing(bytes32 id, address user) external returns (int256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function _.price() external => NONDET;

    // Summarize internals irrelevant to balance tracking.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// HELPERS ///

// Deterministic summary: same inputs always produce the same output.
// This is needed so that balanceOfAfterSlashing (view) agrees with the actual slash.
ghost ghostMulDiv(uint256, uint256, uint256) returns uint256 {
    // mulDivDown(x, y, d) = x * y / d <= x when y <= d. Same holds for mulDivUp.
    axiom forall uint256 x. forall uint256 y. forall uint256 d. y <= d => ghostMulDiv(x, y, d) <= x;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    return ghostMulDiv(x, y, d);
}

/// REPAY ///

/// repay increases onBehalf's balance by exactly obligationUnits, leaves it non-positive,
/// and only changes position[id][onBehalf].balance.
rule repayEffects(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    int256 balanceBefore = balanceOf(id, onBehalf);
    int256 otherBalanceBefore = balanceOf(anyId, anyUser);

    repay(e, obligation, obligationUnits, onBehalf);

    int256 balanceAfter = balanceOf(id, onBehalf);
    int256 otherBalanceAfter = balanceOf(anyId, anyUser);

    assert balanceAfter == balanceBefore + obligationUnits;
    assert balanceAfter <= 0;
    assert anyUser != onBehalf || anyId != id => otherBalanceAfter == otherBalanceBefore;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-slash balance by exactly obligationUnits, leaves it non-negative,
/// and only changes position[id][onBehalf].balance.
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    int256 balanceAfterSlash = balanceOfAfterSlashing(id, onBehalf);
    int256 otherBalanceBefore = balanceOf(anyId, anyUser);

    withdraw(e, obligation, obligationUnits, onBehalf, receiver);

    int256 balanceAfter = balanceOf(id, onBehalf);
    int256 otherBalanceAfter = balanceOf(anyId, anyUser);

    assert balanceAfter == balanceAfterSlash - obligationUnits;
    assert balanceAfter >= 0;
    assert anyUser != onBehalf || anyId != id => otherBalanceAfter == otherBalanceBefore;
}

/// TAKE ///

/// take changes maker's and taker's balances by +/- obligationUnits relative to their post-slash balances,
/// and only changes balances of maker and taker at the obligation id.
rule takeEffects(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);

    int256 makerPostSlash = balanceOfAfterSlashing(id, offer.maker);
    int256 takerPostSlash = balanceOfAfterSlashing(id, taker);
    int256 otherBalanceBefore = balanceOf(anyId, anyUser);

    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    int256 makerAfter = balanceOf(id, offer.maker);
    int256 takerAfter = balanceOf(id, taker);
    int256 otherBalanceAfter = balanceOf(anyId, anyUser);

    mathint makerDelta = offer.buy ? obligationUnits : -obligationUnits;
    assert makerAfter == makerPostSlash + makerDelta;
    mathint takerDelta = offer.buy ? -obligationUnits : obligationUnits;
    assert takerAfter == takerPostSlash + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => otherBalanceAfter == otherBalanceBefore;
}

/// LIQUIDATE ///

/// liquidate increases the borrower's balance by at least repaidUnits, leaves it non-positive
/// when repayment is non-zero, and only changes position[id][borrower].balance.
rule liquidateEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    int256 balanceBefore = balanceOf(id, borrower);
    int256 otherBalanceBefore = balanceOf(anyId, anyUser);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    int256 balanceAfter = balanceOf(id, borrower);
    int256 otherBalanceAfter = balanceOf(anyId, anyUser);

    assert balanceAfter >= balanceBefore + repaidResult;
    assert repaidResult > 0 => balanceAfter <= 0;
    assert anyUser != borrower || anyId != id => otherBalanceAfter == otherBalanceBefore;
}

/// SLASH ///

/// slash can only decrease balances (or keep them unchanged), preserves non-positive balances,
/// leaves the balance non-negative, and only changes position[id][user].balance.
/// Requires the system invariant that the obligation's lossIndex >= the user's lossIndex.
rule slashEffects(env e, bytes32 id, address user, bytes32 anyId, address anyUser) {
    require userLossIndex(id, user) <= currentContract.obligationState[id].lossIndex, "TODO prove this";

    int256 balanceBefore = balanceOf(id, user);
    int256 otherBalanceBefore = balanceOf(anyId, anyUser);

    slash(e, id, user);

    int256 balanceAfter = balanceOf(id, user);
    int256 otherBalanceAfter = balanceOf(anyId, anyUser);

    assert balanceAfter <= balanceBefore;
    assert balanceAfter >= 0;
    assert balanceBefore <= 0 => balanceAfter == balanceBefore;
    assert anyUser != user || anyId != id => otherBalanceAfter == otherBalanceBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, and slash do not change any user's balance.
rule balanceUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:slash(bytes32, address).selector
} {
    int256 balanceBefore = balanceOf(id, user);
    f(e, args);
    int256 balanceAfter = balanceOf(id, user);
    assert balanceAfter == balanceBefore;
}
