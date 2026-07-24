// SPDX-License-Identifier: GPL-2.0-or-later
using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function lossFactor(bytes32 id) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function credit(bytes32 id, address user) external returns (uint128) envfree;
    function lastAccrual(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function continuousFee(bytes32 id) external returns (uint32) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic hash preserves market-to-id relationship without adding assumptions.
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Summarize mulDivDown and mulDivUp to simplify the verification task.
    // Use a ghost function that ensures mulDivDown/Up behaves deterministically and add only the axioms about mulDiv that are needed to prove the desired property.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    // Over-approximate view functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
}

/// HELPERS ///

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition MAX_TTM() returns mathint = 100 * 365 * 86400;

definition WAD() returns uint256 = 10 ^ 18;

definition zeroFloorSub(uint256 a, uint256 b) returns mathint = a >= b ? a - b : 0;

// Monotonic clock: the greatest block.timestamp observed so far. block.timestamp only increases,
// so this lower-bounds every future timestamp. Persistent so callbacks cannot havoc it.
persistent ghost mathint lastTimestamp {
    init_state axiom lastTimestamp == 0;
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

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

/// The up-to-date face value of a lender's position: credit - pendingFee after slashing and fee accrual.
function netCredit(env e, Midnight.Market market, address user) returns mathint {
    bytes32 id = summaryToId(market);
    uint128 credit;
    uint128 pending;
    uint128 accruedFee;
    require pendingFee(id, user) <= credit(id, user), "See pendingContinuousFeeBoundedByCredit in Midnight.spec";
    require lastLossFactor(id, user) <= lossFactor(id), "See lastLossFactorLeqMarketLossFactor in Midnight.spec";
    credit, pending, accruedFee = updatePositionView(e, market, id, user);
    return credit - pending;
}

/// INVARIANTS ///

/// Once a position has been accrued at or after maturity, its pending fee is fully realized and stays
/// at zero: the continuous fee only accrues up to maturity, so there is nothing left to accrue.
/// This implies that the net credit is equal to the credit once a position has been accrued at or after maturity.
invariant pendingFeeZeroAfterMaturity(Midnight.Market market, bytes32 id, address user)
    summaryToId(market) == id && lastAccrual(id, user) >= market.maturity => pendingFee(id, user) == 0;

// A created market's maturity is at most MAX_TTM in the future: touchMarket enforces it at creation
// (MaturityTooFar in Midnight.sol), maturity is immutable, and block.timestamp only increases.
strong invariant maturityBoundedByLastTimestamp(Midnight.Market market)
    marketIsCreated(market) => to_mathint(market.maturity) <= lastTimestamp + MAX_TTM()
    {
        preserved with (env e) {
            require to_mathint(e.block.timestamp) >= lastTimestamp, "block.timestamp is monotonic";
            lastTimestamp = to_mathint(e.block.timestamp);
        }
    }

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
    mathint netCreditBefore = netCredit(e, market, user);

    f(e, args);

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter == netCreditBefore;
}

/// Withdrawing on behalf of another account does not change an unrelated user's net credit.
rule withdrawDoesNotChangeOtherNetCredit(env e, Midnight.Market withdrawMarket, uint256 units, address onBehalf, address receiver, Midnight.Market market, address user) {
    require user != onBehalf || summaryToId(withdrawMarket) != summaryToId(market), "withdrawing for someone else or on another market";

    mathint netCreditBefore = netCredit(e, market, user);

    withdraw(e, withdrawMarket, units, onBehalf, receiver);

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter == netCreditBefore;
}

/// Withdrawing cannot increase net credit.
rule withdrawNetCreditNonIncreasing(env e, Midnight.Market withdrawMarket, uint256 units, address onBehalf, address receiver, Midnight.Market market, address user) {
    mathint netCreditBefore = netCredit(e, market, user);

    withdraw(e, withdrawMarket, units, onBehalf, receiver);

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter <= netCreditBefore;
}

/// Taking does not change the net credit of a user that is neither the taker nor the offer's maker.
rule takeDoesNotChangeOtherNetCredit(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, Midnight.Market market, address user) {
    require (user != taker && user != offer.maker) || summaryToId(offer.market) != summaryToId(market), "user is not involved in the take or another market";

    mathint netCreditBefore = netCredit(e, market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter == netCreditBefore;
}

/// Taking does not decrease the net credit of a buyer in a take, and does not increase the net credit of a seller in a take.
rule takeNetCreditChangeForBuyerAndSeller(env e, Midnight.Offer offer, bytes ratifierData, uint256 units, address taker, address receiver, address takerCallback, bytes takerCallbackData, address user) {
    mathint netCreditBefore = netCredit(e, offer.market, user);

    take(e, offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);

    // We require it after `take`, because `take` may initialize the market first.
    require continuousFee(summaryToId(offer.market)) <= MAX_CONTINUOUS_FEE(), "See continuousFeeBounded in Midnight.sol";
    // maturity <= block.timestamp + MAX_TTM follows from the proven invariant plus timestamp monotonicity.
    requireInvariant maturityBoundedByLastTimestamp(offer.market);
    require to_mathint(e.block.timestamp) >= lastTimestamp, "block.timestamp is monotonic";
    assert continuousFee(summaryToId(offer.market)) * zeroFloorSub(offer.market.maturity, e.block.timestamp) <= WAD(), "interest <= 100%";

    mathint netCreditAfter = netCredit(e, offer.market, user);

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    assert user == buyer => netCreditAfter >= netCreditBefore;
    assert user == seller => netCreditAfter <= netCreditBefore;
}

/// Liquidating does not change any user's net credit as long as no bad debt is realized on the same market,
/// i.e. the market loss factor is unchanged by the liquidation.
rule liquidateWithoutBadDebtDoesNotChangeCredit(env e, Midnight.Market liquidateMarket, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, Midnight.Market market, address user) {
    bytes32 id = summaryToId(market);
    uint128 lossFactorBefore = lossFactor(id);

    mathint netCreditBefore = netCredit(e, market, user);

    liquidate(e, liquidateMarket, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    // Restrict to executions in which no bad debt was realized or that are on other markets.
    require lossFactor(id) == lossFactorBefore || summaryToId(liquidateMarket) != summaryToId(market), "no bad debt realized or on different market";

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter == netCreditBefore;
}

/// Liquidation cannot increase net credit.
rule liquidateNetCreditNonIncreasing(env e, Midnight.Market liquidateMarket, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bool postMaturityMode, address receiver, address callback, bytes data, Midnight.Market market, address user) {
    mathint netCreditBefore = netCredit(e, market, user);

    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => b1 <= b2 => ghostMulDivUp(a, b1, d) <= ghostMulDivUp(a, b2, d), "See mulDivMonotoneB in MulDiv.spec";
    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => a <= d => b2 <= b1 => ghostMulDivUp(a, b1, d) - ghostMulDivUp(a, b2, d) <= b1 - b2, "See mulDivLipschitzB in MulDiv.spec";
    require forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => b <= d => ghostMulDivUp(a, b, d) <= a, "See mulDivArgumentLesserThanDenominator in MulDiv.spec";

    require forall uint256 a. forall uint256 b1. forall uint256 b2. forall uint256 d. d > 0 => b1 <= b2 => ghostMulDivDown(a, b1, d) <= ghostMulDivDown(a, b2, d), "See mulDivMonotoneB in MulDiv.spec";
    require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 => a1 <= a2 => ghostMulDivDown(a1, b, d) <= ghostMulDivDown(a2, b, d), "See mulDivMonotoneA in MulDiv.spec";
    require forall uint256 a1. forall uint256 a2. forall uint256 b. forall uint256 d. d > 0 => b <= d => a1 <= a2 => ghostMulDivDown(a2, b, d) - ghostMulDivDown(a1, b, d) <= a2 - a1, "See mulDivLipschitzA in MulDiv.spec";

    liquidate(e, liquidateMarket, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    mathint netCreditAfter = netCredit(e, market, user);

    assert netCreditAfter <= netCreditBefore;
}
