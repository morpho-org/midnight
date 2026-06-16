// SPDX-License-Identifier: GPL-2.0-or-later
using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function lossFactor(bytes32 id) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function toId(Midnight.Market) external returns (bytes32) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic hash preserves market-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Summarize mulDivDown and mulDivUp to simplify the verification task.
    // Use a ghost function that ensures mulDivDown/Up behaves deterministically and add only the axioms about mulDiv that are needed to prove the desired property.
    // The axioms are proved in MulDiv.spec.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Price/fee/health helpers are non-linear (wExp, fee interpolation, oracle math) but only feed
    // take()'s prices, settlement fees, and the maker/taker positions. The rules that exercise take
    // (takeDoesNotDecreaseUninvolvedCredit) only look at an uninvolved user's position and never the
    // market loss factor, so these are irrelevant to the asserted property. NONDET removes the
    // non-linearity without weakening what we prove.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
}

/// SUMMARY FUNCTIONS ///

persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

/* Axioms that are proved by MulDiv.spec */
definition WAD() returns uint256 = 10 ^ 18;

/* proved in mulDivZero in MulDiv.spec */
definition axiomDownZero(mathint b, mathint d) returns bool = d > 0 => ghostMulDivDown(0, b, d) == 0;

definition axiomDownZero2(mathint a, mathint d) returns bool = d > 0 => ghostMulDivDown(a, 0, d) == 0;

definition axiomUpZero2(mathint a, mathint d) returns bool = d > 0 => ghostMulDivUp(a, 0, d) == 0;

/* proved in mulDivIdentity in MulDiv.spec */
definition axiomDownIdentity(mathint a, mathint b) returns bool = b > 0 => ghostMulDivDown(a, b, b) == a;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivDown(a, b, d));
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(ghostMulDivUp(a, b, d));
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

/// The up-to-date face value of a lender's position: credit - pendingFee after slashing and fee accrual.
/// The continuous fee cancels out (it is subtracted from both credit and pendingFee), so this only
/// reflects withdrawals, take transfers, and bad-debt slashing via the market loss factor.
function netCredit(env e, Midnight.Market market, address user) returns mathint {
    bytes32 id = toId(market);
    uint128 credit;
    uint128 pending;
    uint128 accruedFee;
    require pendingFee(id, user) <= creditOf(id, user), "See pendingContinuousFeeBoundedByCredit in Midnight.spec";
    credit, pending, accruedFee = updatePositionView(e, market, id, user);
    return credit - pending;
}

/// INVARIANTS ///

/// Once a position has been accrued at or after maturity, its pending fee is fully realized and stays
/// at zero: the continuous fee only accrues up to maturity, so there is nothing left to accrue.
invariant pendingFeeZeroAfterMaturity(Midnight.Market market, address user)
    lastAccrual(toId(market), user) >= market.maturity => pendingFee(toId(market), user) == 0
    {
        preserved with (env e) {
            require(forall mathint b. forall mathint d. axiomDownZero(b, d)), "axiom";
            require(forall mathint a. forall mathint d. axiomDownZero2(a, d)), "axiom";
            require(forall mathint a. forall mathint b. axiomDownIdentity(a, b)), "axiom";
        }
    }

/// RULES ///

/// The up-to-date face value of a lender's position (credit - pendingFee) can only decrease by
/// withdrawing, taking, or liquidating. Every other function leaves it unchanged or increases it.
rule creditNondecreasing(env e, method f, calldataarg args, Midnight.Market market, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
} {
    mathint creditBefore = netCredit(e, market, user);

    require(forall mathint a. forall mathint d. axiomDownZero2(a, d)), "axiom";
    require(forall mathint a. forall mathint d. axiomUpZero2(a, d)), "axiom";
    require(forall mathint a. forall mathint b. axiomDownIdentity(a, b)), "axiom";

    f(e, args);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Withdrawing on behalf of another account does not decrease an unrelated user's net credit.
rule withdrawDoesNotDecreaseOtherCredit(env e, Midnight.Market market, uint256 units, address onBehalf, address receiver, address user) {
    require user != onBehalf, "withdrawing for someone else";

    mathint creditBefore = netCredit(e, market, user);

    withdraw(e, market, units, onBehalf, receiver);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Taking does not decrease the net credit of a user that is neither the taker nor the offer's maker.
rule takeDoesNotDecreaseUninvolvedCredit(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    require user != taker && user != offer.maker, "user is not involved in the take";

    mathint creditBefore = netCredit(e, offer.market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    mathint creditAfter = netCredit(e, offer.market, user);

    assert creditAfter == creditBefore;
}

/// Liquidating does not decrease any user's net credit as long as no bad debt is realized,
/// i.e. the market loss factor is unchanged by the liquidation.
rule liquidateWithoutBadDebtDoesNotDecreaseCredit(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, address user) {
    bytes32 id = toId(market);
    uint128 lossFactorBefore = lossFactor(id);

    mathint creditBefore = netCredit(e, market, user);

    liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    // Restrict to executions in which no bad debt was realized.
    require lossFactor(id) == lossFactorBefore, "no bad debt realized";

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}
