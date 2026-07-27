// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function claimableSettlementFee(address token) external returns (uint256) envfree;
    function credit(bytes32 id, address user) external returns (uint128) envfree;
    function debt(bytes32 id, address user) external returns (uint128) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
    function lastLossFactor(bytes32 id, address user) external returns (uint128) envfree;
    function tickSpacing(bytes32 id) external returns (uint8) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory) internal returns (address) => NONDET;
    function settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;

    // Over-approximate view functions.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
}

/// HELPERS ///

definition MAX_CONTINUOUS_FEE() returns uint256 = 317097919;

definition MAX_TTM() returns mathint = 100 * 365 * 86400;

definition WAD() returns uint256 = 10 ^ 18;

persistent ghost mapping(bytes32 => uint256) maturityOfId;

function summaryToId(Midnight.Market market) returns (bytes32) {
    bytes32 id = Utils.hashMarket(market);
    require maturityOfId[id] == to_mathint(market.maturity), "remember the maturity of the market";
    return id;
}

function marketIsCreated(Midnight.Market market) returns (bool) {
    return tickSpacing(summaryToId(market)) > 0;
}

persistent ghost mapping(bytes32 => mathint) sumDebt {
    init_state axiom (forall bytes32 id. sumDebt[id] == 0);
}

hook Sstore position[KEY bytes32 id][KEY address owner].debt uint128 newDebt (uint128 oldDebt) {
    sumDebt[id] = sumDebt[id] - to_mathint(oldDebt) + to_mathint(newDebt);
}

// Monotonic clock: the greatest block.timestamp observed so far. block.timestamp only increases,
// so this lower-bounds every future timestamp. Persistent so callbacks cannot havoc it.
persistent ghost uint256 lastTimestamp;

hook TIMESTAMP() uint newTimestamp {
    require newTimestamp >= lastTimestamp, "timestamps are guaranteed to be increasing";

    require newTimestamp < 2 ^ 63, "safe as it corresponds to some time very far into the future";
    lastTimestamp = newTimestamp;
}

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    uint256 r;
    require x == 0 => r == 0, "see mulDivZero";
    require d > 0 && y <= d => r <= x, "see mulDivArgumentLesserThanDenominator";
    require d > 0 && x <= d && y <= d => x - r <= d - y, "see mulDivResidualBound";
    return r;
}

rule takeInputOutputConsistency(env e, Midnight.Offer offer, bytes ratifierData, uint256 unitsInput, address taker, address receiver, address takerCallbackAddress, bytes takerCallbackData) {
    uint256 buyerAssetsOutput;
    uint256 sellerAssetsOutput;

    uint256 claimableBefore = claimableSettlementFee(offer.market.loanToken);

    buyerAssetsOutput, sellerAssetsOutput = take(e, offer, ratifierData, unitsInput, taker, receiver, takerCallbackAddress, takerCallbackData);

    // If the input is zero, all the output arguments are zero.
    assert unitsInput == 0 => buyerAssetsOutput == 0 && sellerAssetsOutput == 0;

    // The claimable settlement fee increases by exactly the spread.
    assert claimableSettlementFee(offer.market.loanToken) == claimableBefore + buyerAssetsOutput - sellerAssetsOutput;
}

rule liquidateInputOutputConsistency(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, bool postMaturityMode) {
    uint256 seizedAssetsOutput;
    uint256 repaidUnitsOutput;

    seizedAssetsOutput, repaidUnitsOutput = liquidate(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, postMaturityMode, receiver, callback, data);

    // At most one of the input arguments can be zero.
    assert seizedAssets == 0 || repaidUnits == 0;

    // The output arguments are equal to the input arguments if the input arguments are non-zero.
    assert seizedAssets == 0 || seizedAssetsOutput == seizedAssets;
    assert repaidUnits == 0 || repaidUnitsOutput == repaidUnits;

    // If all the input arguments are zero, all the output arguments are zero.
    assert repaidUnits == 0 && seizedAssets == 0 => seizedAssetsOutput == 0 && repaidUnitsOutput == 0;
}

rule marketLossFactorMonotonicallyIncreases(bytes32 id, method f, env e, calldataarg args) {
    uint128 lossFactorBefore = currentContract.marketState[id].lossFactor;
    f(e, args);
    uint128 lossFactorAfter = currentContract.marketState[id].lossFactor;
    assert lossFactorAfter >= lossFactorBefore;
}

rule lastLossFactorMonotonicallyIncreases(bytes32 id, address user, method f, env e, calldataarg args) {
    requireInvariant lastLossFactorLeqMarketLossFactor(id, user);
    uint128 lastLossFactorBefore = lastLossFactor(id, user);
    f(e, args);
    uint128 lastLossFactorAfter = lastLossFactor(id, user);
    assert lastLossFactorAfter >= lastLossFactorBefore;
}

rule creditAndDebtCannotIncreaseWhenLossFactorIsMaxed(bytes32 id, address user, method f, env e, calldataarg args) {
    require currentContract.marketState[id].lossFactor == max_uint128, "assume loss factor is maxed out";
    uint256 creditBefore = credit(id, user);
    uint256 debtBefore = debt(id, user);

    f(e, args);

    assert credit(id, user) <= creditBefore;
    assert debt(id, user) <= debtBefore;
}

/// INVARIANTS ///

strong invariant totalUnitsEqualsSumNegativeDebtPlusWithdrawable(bytes32 id)
    to_mathint(totalUnits(id)) == sumDebt[id] + to_mathint(withdrawable(id));

strong invariant defaultContinuousFeeBoundedAll()
    forall address token. currentContract.defaultContinuousFee[token] <= MAX_CONTINUOUS_FEE();

strong invariant continuousFeeBounded(bytes32 id)
    currentContract.marketState[id].continuousFee <= MAX_CONTINUOUS_FEE()
    {
        preserved with (env e) {
            requireInvariant defaultContinuousFeeBoundedAll();
        }
    }

// A created market's maturity, recorded in maturityOfId at creation, is at most MAX_TTM in the future.
strong invariant maturityBoundedById(bytes32 id)
    tickSpacing(id) > 0 => maturityOfId[id] <= lastTimestamp + MAX_TTM();

strong invariant pendingContinuousFeeBoundedByCredit(bytes32 id, address user)
    pendingFee(id, user) <= credit(id, user)
    {
        preserved with (env e) {
            requireInvariant continuousFeeBounded(id);
            requireInvariant defaultContinuousFeeBoundedAll();
        }
        preserved take(Midnight.Offer offer, bytes ratifierData, uint256 unitsInput, address taker, address receiverIfTakerIsSeller, address takerCallbackAddress, bytes takerCallbackData) with (env e) {
            requireInvariant continuousFeeBounded(id);
            requireInvariant defaultContinuousFeeBoundedAll();
            requireInvariant maturityBoundedById(summaryToId(offer.market));
        }
    }

rule noRemainingContinuousFeeWithoutCredit(bytes32 id, address user) {
    requireInvariant pendingContinuousFeeBoundedByCredit(id, user);
    assert credit(id, user) == 0 => pendingFee(id, user) == 0;
}

strong invariant lastLossFactorLeqMarketLossFactor(bytes32 id, address user)
    lastLossFactor(id, user) <= currentContract.marketState[id].lossFactor;

/// A user cannot have both credit and debt.
strong invariant noCreditAndDebt(bytes32 id, address user)
    credit(id, user) == 0 || debt(id, user) == 0;

strong invariant enabledLltvIsLessThanOrEqualToOne(uint256 lltv)
    currentContract.isLltvEnabled[lltv] => lltv <= WAD();

strong invariant enabledLiquidationCursorsIsLessThanOne(uint256 liquidationCursor)
    currentContract.isLiquidationCursorEnabled[liquidationCursor] => liquidationCursor < WAD();
