// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function Utils.callbackSuccess() external returns (bytes32) envfree;

    // Oracle: routed through CVL function to allow ghost flags to force specific behaviors (revert, return zero) per rule.
    // calledContract is used to target a single oracle address for per-oracle revert control (used by oracle revert/zero rules).
    function _.price() external => CVL_oraclePrice(calledContract) expect(uint256);

    // Gates: routed through CVL functions using calledContract to identify which gate is being called.
    // Return values are deterministic per gate address via ghost functions, so
    // rules can constrain a specific gate's return value without affecting other gates. Each call can also
    // nondeterministically revert, modeling that external gates can fail for any reason.
    function _.canIncreaseCredit(address) external => summaryCanIncreaseCredit(calledContract) expect(bool);
    function _.canIncreaseDebt(address) external => summaryCanIncreaseDebt(calledContract) expect(bool);
    function _.canLiquidate(address) external => summaryCanLiquidate(calledContract) expect(bool);

    // Callbacks: ghost-controlled to force revert/bad-return per rule. Modeled as pure (no state changes):
    // For callback-revert rules, the callback reverts so that it's equivalent to the real behavior of EVM.
    // For gate rules, gate checks precede callbacks so re-entrant state changes cannot affect them.
    // For oracle rules, re-entrant callbacks cannot deactivate collaterals without calling
    // withdrawCollateral -> isHealthy which would hit the same reverting/zero oracle.
    function _.onBuy(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onSell(bytes32, Midnight.Market, address, uint256, uint256, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.isRatified(Midnight.Offer, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onRepay(bytes32, Midnight.Market, uint256, address, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onLiquidate(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onFlashLoan(address[], uint256[], bytes) external => CVL_callbackBytes32() expect(bytes32);

    // Token transfers: routed through CVL functions to force revert per rule. Modeled as no-op on success
    // (no balance tracking), which is sound for revert-propagation rules.
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => CVL_safeTransferFrom();
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => CVL_safeTransfer();

    // Bitmap operations (msb, clearBit, setBit) are provided by BitmapSummaries.spec.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // The function toMarket is not used by the protocol.
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;
    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);
}

// needed for oracle returns zero case
persistent ghost CVL_mulDivDownGhost(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 d. d > 0 => CVL_mulDivDownGhost(a, 0, d) == 0;
    axiom forall uint256 b. forall uint256 d. d > 0 => CVL_mulDivDownGhost(0, b, d) == 0;
}

// needed for oracle returns zero case
persistent ghost CVL_mulDivUpGhost(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 d. d > 0 => CVL_mulDivUpGhost(a, 0, d) == 0;
    axiom forall uint256 b. forall uint256 d. d > 0 => CVL_mulDivUpGhost(0, b, d) == 0;
}

function CVL_mulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return CVL_mulDivDownGhost(a, b, d);
}

function CVL_mulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return CVL_mulDivUpGhost(a, b, d);
}

/// GHOST FLAGS ///

persistent ghost bool forceOracleRevert;

// Per-oracle revert: only the oracle at this address reverts.
persistent ghost address singleRevertingOracle;

persistent ghost bool forceOracleReturnZero;

// Per-oracle zero return: only the oracle at this address returns 0.
persistent ghost address singleZeroOracle;

persistent ghost ghostCanIncreaseCredit(address) returns bool;

persistent ghost ghostCanIncreaseDebt(address) returns bool;

persistent ghost ghostCanLiquidate(address) returns bool;

persistent ghost bool forceCallbackRevert;

persistent ghost bool forceCallbackBadReturn;

persistent ghost bool forceTransferRevert;

persistent ghost bool forceTransferFromRevert;

/// SUMMARIES ///

function summaryToId(Midnight.Market market) returns (bytes32) {
    return Utils.hashMarket(market);
}

function CVL_oraclePrice(address oracle) returns uint256 {
    bool shouldRevert;
    if (shouldRevert || forceOracleRevert || oracle == singleRevertingOracle) {
        revert();
    }
    if (forceOracleReturnZero || oracle == singleZeroOracle) {
        return 0;
    }
    uint256 price;
    return price;
}

function summaryCanIncreaseCredit(address gate) returns bool {
    bool shouldRevert;
    if (shouldRevert) {
        revert();
    }
    return ghostCanIncreaseCredit(gate);
}

function summaryCanIncreaseDebt(address gate) returns bool {
    bool shouldRevert;
    if (shouldRevert) {
        revert();
    }
    return ghostCanIncreaseDebt(gate);
}

function summaryCanLiquidate(address gate) returns bool {
    bool shouldRevert;
    if (shouldRevert) {
        revert();
    }
    return ghostCanLiquidate(gate);
}

function CVL_callbackBytes32() returns bytes32 {
    bool shouldRevert;
    if (shouldRevert || forceCallbackRevert) {
        revert();
    }
    if (forceCallbackBadReturn) {
        bytes32 bad;
        require bad != Utils.callbackSuccess(), "not CALLBACK_SUCCESS";
        return bad;
    }
    bytes32 result;
    return result;
}

function CVL_safeTransferFrom() {
    bool shouldRevert;
    if (shouldRevert || forceTransferFromRevert) {
        revert();
    }
}

function CVL_safeTransfer() {
    bool shouldRevert;
    if (shouldRevert || forceTransferRevert) {
        revert();
    }
}

/// ORACLE REVERT PROPAGATION ///

/// If any activated collateral oracle reverts on price, liquidate reverts.
rule oracleRevertCausesLiquidateRevert(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data, uint256 revertingCollateralIndex) {
    require singleRevertingOracle == market.collateralParams[revertingCollateralIndex].oracle, "oracle is reverting";

    bytes32 id = summaryToId(market);
    uint128 bitmap = collateralBitmap(id, borrower);
    require summaryGetBit(bitmap, revertingCollateralIndex), "revertingCollateralIndex is activated";

    liquidate@withrevert(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    assert lastReverted;
}

/// If an activated collateral oracle reverts on price different than withdrawn collateral, withdrawCollateral reverts when the borrower has debt.
rule oracleRevertCausesWithdrawCollateralRevert(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, uint256 revertingCollateralIndex) {
    require singleRevertingOracle == market.collateralParams[revertingCollateralIndex].oracle, "oracle is reverting";
    require revertingCollateralIndex < 128, "clearBit produces a new bitmap whose summaryGetBit is unconstrained for indices >= 128";
    require revertingCollateralIndex != collateralIndex, "withdrawCollateral may clear the bit at collateralIndex before calling isHealthy";

    bytes32 id = summaryToId(market);
    uint128 bitmap = collateralBitmap(id, onBehalf);
    require summaryGetBit(bitmap, revertingCollateralIndex), "revertingCollateralIndex is activated";

    withdrawCollateral@withrevert(e, market, collateralIndex, assets, onBehalf, receiver);
    bool reverted = lastReverted;

    assert debtOf(id, onBehalf) > 0 => reverted;
}

/// If an activated collateral oracle reverts on price, isHealthy reverts when the borrower has debt.
rule oracleRevertCausesIsHealthyRevert(env e, Midnight.Market market, bytes32 id, address borrower, uint256 collateralIndex) {
    require singleRevertingOracle == market.collateralParams[collateralIndex].oracle, "oracle is reverting";

    uint128 bitmap = collateralBitmap(id, borrower);
    require summaryGetBit(bitmap, collateralIndex), "collateralIndex is activated";

    isHealthy@withrevert(e, market, id, borrower);
    bool reverted = lastReverted;

    assert debtOf(id, borrower) > 0 => reverted;
}

/// If an activated collateral oracle reverts on price and take succeeds, the seller must have no debt.
rule oracleRevertPreventsTakeWhenSellerHasDebt(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, uint256 collateralIndex) {
    require singleRevertingOracle == offer.market.collateralParams[collateralIndex].oracle, "oracle is reverting";

    bytes32 id = summaryToId(offer.market);
    address seller = offer.buy ? taker : offer.maker;

    // Without this, take's liquidatability check short-circuits to false (without calling isHealthy) because
    // take's tExchange keeps the lock set when wasLocked is true, so the oracle is never queried.
    require !liquidationLocked(id, seller), "seller is not liquidation locked";

    uint128 bitmap = collateralBitmap(id, seller);
    require summaryGetBit(bitmap, collateralIndex), "collateralIndex is activated";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    assert debtOf(id, seller) == 0;
}

/// ORACLE RETURNS ZERO ///

/// If liquidated collateral oracle returns 0 on price, liquidate with repaid input reverts.
rule oracleZeroCausesLiquidateWithRepaidRevert(env e, Midnight.Market market, uint256 collateralIndex, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require singleZeroOracle == market.collateralParams[collateralIndex].oracle, "oracle returns zero";
    require repaidUnits > 0, "using repaid units as input";

    liquidate@withrevert(e, market, collateralIndex, 0, repaidUnits, borrower, receiver, callback, data);

    assert lastReverted;
}

/// If all oracles return 0 and the borrower has debt, isHealthy returns false.
rule oracleZeroCausesIsHealthyReturnFalse(env e, Midnight.Market market, address borrower) {
    require forceOracleReturnZero, "all oracles return zero";

    bytes32 id = summaryToId(market);
    require collateralBitmap(id, borrower) != 0, "borrower has activated collaterals";

    bool healthy = isHealthy(e, market, id, borrower);

    assert debtOf(id, borrower) > 0 => !healthy;
}

/// If all oracles return 0, withdrawCollateral reverts when the borrower has debt.
rule oracleZeroPreventsWithdrawWhenBorrowerHasDebt(env e, Midnight.Market market, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    require forceOracleReturnZero, "all oracles return zero";

    bytes32 id = summaryToId(market);
    require collateralBitmap(id, onBehalf) != 0, "borrower has activated collaterals";

    withdrawCollateral(e, market, collateralIndex, assets, onBehalf, receiver);

    assert debtOf(id, onBehalf) == 0;
}

/// If all oracles return 0 and take succeeds, the seller must have no debt.
rule oracleZeroPreventsTakeWhenSellerHasDebt(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData) {
    require forceOracleReturnZero, "all oracles return zero";

    bytes32 id = summaryToId(offer.market);
    address seller = offer.buy ? taker : offer.maker;
    require !liquidationLocked(id, seller), "seller is not liquidation locked";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    assert debtOf(id, seller) == 0;
}

/// GATE BLOCKING ///

/// If enterGate.canIncreaseCredit returns false and take succeeds, no user's credit increases.
rule enterGateBlocksCreditIncrease(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, address user) {
    require !ghostCanIncreaseCredit(offer.market.enterGate), "canIncreaseCredit blocked";
    require offer.market.enterGate != 0, "enter gate is set";

    bytes32 id = summaryToId(offer.market);
    uint256 creditBefore = creditOf(id, user);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    uint256 creditAfter = creditOf(id, user);

    assert creditAfter <= creditBefore;
}

/// If enterGate.canIncreaseDebt returns false and take succeeds, no user's debt increases.
rule enterGateBlocksDebtIncrease(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, address user) {
    require !ghostCanIncreaseDebt(offer.market.enterGate), "canIncreaseDebt blocked";
    require offer.market.enterGate != 0, "enter gate is set";

    bytes32 id = summaryToId(offer.market);
    uint256 debtBefore = debtOf(id, user);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    uint256 debtAfter = debtOf(id, user);

    assert debtAfter <= debtBefore;
}

/// If the liquidator gate returns false on canLiquidate, liquidate reverts.
rule liquidatorGateBlocksLiquidation(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require !ghostCanLiquidate(market.liquidatorGate), "canLiquidate blocked";
    require market.liquidatorGate != 0, "liquidator gate is set";

    liquidate@withrevert(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    assert lastReverted;
}

/// TOKEN TRANSFER REVERT PROPAGATION ///

/// If transferFrom reverts, take, repay, supplyCollateral, and liquidate all revert.
rule transferFromRevertPropagation(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes).selector
        || f.selector == sig:repay(Midnight.Market, uint256, address, address, bytes).selector
        || f.selector == sig:supplyCollateral(Midnight.Market, uint256, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    require forceTransferFromRevert, "transferFrom reverts";
    f@withrevert(e, args);
    assert lastReverted;
}

/// If transferFrom reverts, flashLoan reverts, assuming that the arrays are not empty.
rule transferFromRevertPropagationFlashLoan(env e, address[] tokens, uint256[] assets, address callback, bytes data) {
    require forceTransferFromRevert, "transferFrom reverts";
    require tokens.length > 0, "assume tokens array is not empty";
    flashLoan@withrevert(e, tokens, assets, callback, data);
    assert lastReverted;
}

/// If transfer reverts, withdraw, withdrawCollateral, fee claims, and liquidate all revert.
rule transferRevertPropagation(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:withdraw(Midnight.Market, uint256, address, address).selector
        || f.selector == sig:withdrawCollateral(Midnight.Market, uint256, uint256, address, address).selector
        || f.selector == sig:claimTradingFee(address, uint256, address).selector
        || f.selector == sig:claimContinuousFee(Midnight.Market, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Market, uint256, uint256, uint256, address, address, address, bytes).selector
} {
    require forceTransferRevert, "transfer reverts";
    f@withrevert(e, args);
    assert lastReverted;
}

/// If transfer reverts, flashLoan reverts, assuming that the arrays are not empty.
rule transferRevertPropagationFlashLoan(env e, address[] tokens, uint256[] assets, address callback, bytes data) {
    require forceTransferRevert, "transfer reverts";
    require tokens.length > 0, "assume tokens array is not empty";
    flashLoan@withrevert(e, tokens, assets, callback, data);
    assert lastReverted;
}

/// CALLBACK REVERT PROPAGATION ///

/// If the callback reverts or returns something other than CALLBACK_SUCCESS, callback-enabled repay (non-zero callback) reverts.
rule callbackRevertOrBadReturnCausesRepayRevert(env e, Midnight.Market market, uint256 units, address onBehalf, address callback, bytes data) {
    require forceCallbackRevert || forceCallbackBadReturn, "callback reverts or returns bad value";
    require callback != 0, "callback-enabled repay";

    repay@withrevert(e, market, units, onBehalf, callback, data);

    assert lastReverted;
}

/// If the callback reverts or returns something other than CALLBACK_SUCCESS, callback-enabled liquidate (non-zero callback) reverts.
rule callbackRevertOrBadReturnCausesLiquidateRevert(env e, Midnight.Market market, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, address receiver, address callback, bytes data) {
    require forceCallbackRevert || forceCallbackBadReturn, "callback reverts or returns bad value";
    require callback != 0, "callback-enabled liquidate";

    liquidate@withrevert(e, market, collateralIndex, seizedAssets, repaidUnits, borrower, receiver, callback, data);

    assert lastReverted;
}

/// If the callback reverts or returns something other than CALLBACK_SUCCESS, flashLoan reverts, assuming that the arrays are not empty.
rule callbackRevertOrBadReturnCausesFlashLoanRevert(env e, address[] tokens, uint256[] assets, address callback, bytes data) {
    require forceCallbackRevert || forceCallbackBadReturn, "callback reverts or returns bad value";
    require tokens.length > 0, "assume tokens array is not empty";

    flashLoan@withrevert(e, tokens, assets, callback, data);

    assert lastReverted;
}

/// If a buy/sell/isRatified callback reverts or returns something other than CALLBACK_SUCCESS, take reverts.
rule callbackRevertOrBadReturnCausesTakeRevert(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData) {
    require forceCallbackRevert || forceCallbackBadReturn, "callback reverts or returns bad value";
    require takerCallback != 0 || offer.callback != 0 || offer.ratifier != 0, "callback-enabled take";

    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData);

    assert lastReverted;
}
