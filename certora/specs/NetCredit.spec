// SPDX-License-Identifier: GPL-2.0-or-later
using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function lossFactor(bytes32 id) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function toId(Midnight.Market) external returns (bytes32) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic hash preserves market-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Summarize mulDivDown and mulDivUp to simplify the verification task.
    // Use a ghost function that ensures mulDivDown/Up behaves deterministically and add only the axioms about mulDiv that are needed to prove the desired property.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Over-approximate view functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
}

/// SUMMARY FUNCTIONS ///

persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(0, b, d) == 0;
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivDown(a, 0, d) == 0;

    /* proved in mulDivIdentity in MulDiv.spec */
    axiom forall uint256 a. forall uint256 b. b > 0 => ghostMulDivDown(a, b, b) == a;

    /* proved in mulDivArgumentLesserThanDenominator in MulDiv.spec */
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && b <= d => ghostMulDivDown(a, b, d) <= a;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 a. forall uint256 d. d > 0 => ghostMulDivUp(a, 0, d) == 0;

    /* proved in mulDivArgumentLesserThanDenominator in MulDiv.spec */
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && a <= d => ghostMulDivUp(a, b, d) <= b;

    /* proved in mulDivResidualBound in MulDiv.spec */
    axiom forall uint256 a. forall uint256 b. forall uint256 d. a <= d && b <= d => a - ghostMulDivUp(a, b, d) <= d - b;
}

definition WAD() returns uint256 = 10 ^ 18;

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

/// The up-to-date face value of a lender's position: credit - pendingFee after slashing and fee accrual.
function netCredit(env e, Midnight.Market market, address user) returns mathint {
    bytes32 id = toId(market);
    uint128 credit;
    uint128 pending;
    uint128 accruedFee;
    require pendingFee(id, user) <= creditOf(id, user), "See pendingContinuousFeeBoundedByCredit in Midnight.spec";
    require lastLossFactor(id, user) <= lossFactor(id), "See lastLossFactorLeqMarketLossFactor in Midnight.spec";
    credit, pending, accruedFee = updatePositionView(e, market, id, user);
    return credit - pending;
}

/// INVARIANTS ///

/// Once a position has been accrued at or after maturity, its pending fee is fully realized and stays
/// at zero: the continuous fee only accrues up to maturity, so there is nothing left to accrue.
/// This implies that the net credit is equal to the credit once a position has been accrued at or after maturity.
invariant pendingFeeZeroAfterMaturity(Midnight.Market market, bytes32 id, address user)
    toId(market) == id && lastAccrual(id, user) >= market.maturity => pendingFee(id, user) == 0;

/// RULES ///

/// The up-to-date face value of a lender's position (credit - pendingFee) can only change by
/// withdrawing, taking, or liquidating. Every other function leaves it unchanged.
rule netCreditUnaffected(env e, method f, calldataarg args, Midnight.Market market, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:withdraw(Midnight.Market, uint256, address, address).selector
        && f.selector != sig:take(Midnight.Offer, bytes, uint256, address, address, address, bytes).selector
        && f.selector != sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, bool, address, address, bytes).selector
} {
    mathint creditBefore = netCredit(e, market, user);

    f(e, args);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Withdrawing on behalf of another account does not change an unrelated user's net credit.
rule withdrawDoesNotChangeOtherNetCredit(env e, Midnight.Market withdrawMarket, uint256 units, address onBehalf, address receiver, Midnight.Market market, address user) {
    require user != onBehalf || toId(withdrawMarket) != toId(market), "withdrawing for someone else or on another market";

    mathint creditBefore = netCredit(e, market, user);

    withdraw(e, withdrawMarket, units, onBehalf, receiver);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Withdrawing cannot increase net credit.
rule withdrawNetCreditNonIncreasing(env e, Midnight.Market withdrawMarket, uint256 units, address onBehalf, address receiver, Midnight.Market market, address user) {
    mathint creditBefore = netCredit(e, market, user);

    withdraw(e, withdrawMarket, units, onBehalf, receiver);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter <= creditBefore;
}

/// Taking does not change the net credit of a user that is neither the taker nor the offer's maker.
rule takeDoesNotChangeOtherNetCredit(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, Midnight.Market market, address user) {
    require (user != taker && user != offer.maker) || toId(offer.market) != toId(market), "user is not involved in the take or another market";

    mathint creditBefore = netCredit(e, market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Taking does not decrease the net credit of a buyer in a take, and does not increase the net credit of a seller in a take.
rule takeNetCreditChangeForBuyerAndSeller(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    mathint timeToMaturity = offer.market.maturity > e.block.timestamp ? offer.market.maturity - e.block.timestamp : 0;

    mathint creditBefore = netCredit(e, offer.market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    // This follows from continuousFeeBounded in Midnight.sol under the asssumption
    // that maturity is not more than 100 years in the future.
    // We require it after `take`, because `take` may initialize the market first.
    require continuousFee(toId(offer.market)) * timeToMaturity <= WAD(), "continuousFee * timeToMaturity bounded by WAD";

    mathint creditAfter = netCredit(e, offer.market, user);

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    assert user == buyer => creditAfter >= creditBefore;
    assert user == seller => creditAfter <= creditBefore;
}

/// Liquidating does not change any user's net credit as long as no bad debt is realized,
/// i.e. the market loss factor is unchanged by the liquidation.
rule liquidateWithoutBadDebtDoesNotChangeCredit(env e, Midnight.Market liquidateMarket, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, Midnight.Market market, address user) {
    bytes32 id = toId(market);
    uint128 lossFactorBefore = lossFactor(id);

    mathint creditBefore = netCredit(e, market, user);

    liquidate(e, liquidateMarket, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    // Restrict to executions in which no bad debt was realized.
    require lossFactor(id) == lossFactorBefore || toId(liquidateMarket) != toId(market), "no bad debt realized or on different market";

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter == creditBefore;
}

/// Liquidation cannot increase net credit.
rule liquidateNetCreditNonIncreasing(env e, Midnight.Market liquidateMarket, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, Midnight.Market market, address user) {
    mathint creditBefore = netCredit(e, market, user);

    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => b1 <= b2 => ghostMulDivUp(a, b1, d) <= ghostMulDivUp(a, b2, d);
    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => a <= d => b2 <= b1 => ghostMulDivUp(a, b1, d) - ghostMulDivUp(a, b2, d) <= b1 - b2;
    require forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => b <= d => ghostMulDivUp(a, b, d) <= a;

    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => b1 <= b2 => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d);
    require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 => a1 <= a2 => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d);
    require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 => b <= d => a1 <= a2 => ghostMulDivDown(a2, b, d) - ghostMulDivDown(a1, b, d) <= a2 - a1;

    liquidate(e, liquidateMarket, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    mathint creditAfter = netCredit(e, market, user);

    assert creditAfter <= creditBefore;
}
