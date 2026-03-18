// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function creditAfterSlashing(bytes32 id, address user) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function _.price() external => NONDET;

    // Summarize internals irrelevant to credit and debt tracking.
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
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// HELPERS ///

// Deterministic summary: same inputs always produce the same output.
// This is needed so that creditAfterSlashing (view) agrees with the actual slash.
ghost ghostMulDiv(uint256, uint256, uint256) returns uint256 {
    // mulDivDown(x, y, d) = x * y / d <= x when y <= d. Same holds for mulDivUp.
    axiom forall uint256 x. forall uint256 y. forall uint256 d. y <= d => ghostMulDiv(x, y, d) <= x;

    // x * y / y == x (identity when numerator equals denominator).
    axiom forall uint256 x. forall uint256 y. ghostMulDiv(x, y, y) == x;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    return ghostMulDiv(x, y, d);
}

/// REPAY ///

/// repay decreases onBehalf's debt by exactly obligationUnits and only changes position[id][onBehalf].debt.
rule repayEffects(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    repay(e, obligation, obligationUnits, onBehalf);

    assert debtOf(id, onBehalf) == debtBefore - obligationUnits;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != onBehalf || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-slash credit by exactly obligationUnits, and only changes position[id][onBehalf].credit.
rule withdrawEffects(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 creditPostSlash = creditAfterSlashing(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    withdraw(e, obligation, obligationUnits, onBehalf, receiver);

    assert creditOf(id, onBehalf) == creditPostSlash - obligationUnits;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyUser != onBehalf || anyId != id => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// TAKE ///

/// take changes maker's and taker's net credit and debt by +/- obligationUnits relative to their post-slash values,
/// and only changes credit and debt of maker and taker at the obligation id.
rule takeEffects(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);

    mathint makerPostSlash = to_mathint(creditAfterSlashing(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerPostSlash = to_mathint(creditAfterSlashing(id, taker)) - to_mathint(debtOf(id, taker));
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    mathint makerAfter = to_mathint(creditOf(id, offer.maker)) - to_mathint(debtOf(id, offer.maker));
    mathint takerAfter = to_mathint(creditOf(id, taker)) - to_mathint(debtOf(id, taker));

    mathint makerDelta = offer.buy ? obligationUnits : -obligationUnits;
    assert makerAfter == makerPostSlash + makerDelta;
    mathint takerDelta = offer.buy ? -obligationUnits : obligationUnits;
    assert takerAfter == takerPostSlash + takerDelta;
    assert anyId != id || (anyUser != offer.maker && anyUser != taker) => creditOf(anyId, anyUser) == otherCreditBefore && debtOf(anyId, anyUser) == otherDebtBefore;
}

/// LIQUIDATE ///

/// liquidate decreases the borrower's debt by at least repaidUnits,
/// and only changes position[id][borrower].debt.
rule liquidateEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, borrower);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert debtOf(id, borrower) <= debtBefore - repaidResult;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != borrower || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// SLASH ///

/// slash can only decrease credit (or keep it unchanged), does not change debt,
/// and only changes position[id][user].
/// Requires the system invariant that the obligation's lossIndex >= the user's lossIndex.
rule slashEffects(env e, bytes32 id, address user, bytes32 anyId, address anyUser) {
    require userLossIndex(id, user) <= currentContract.obligationState[id].lossIndex, "TODO prove this";

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);
    uint256 expectedCredit = creditAfterSlashing(id, user);

    slash(e, id, user);

    assert creditOf(id, user) == expectedCredit;
    assert debtOf(anyId, anyUser) == otherDebtBefore;
    assert anyUser != user || anyId != id => creditOf(anyId, anyUser) == otherCreditBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, and slash do not change any user's credit or debt.
rule creditAndDebtUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:slash(bytes32, address).selector
} {
    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    assert creditOf(id, user) == creditBefore;
    assert debtOf(id, user) == debtBefore;
}
