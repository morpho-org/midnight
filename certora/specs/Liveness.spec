// SPDX-License-Identifier: GPL-2.0-or-later

// Liveness properties from Midnight.sol (lines 85-99).
// These rules verify that external dependency failures (oracle, gate, callback, token transfer)
// correctly propagate as reverts to the affected user-facing functions.

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // envfree view functions
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function activatedCollaterals(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;

    // Oracle summary: ghost-controlled
    function _.price() external => CVL_oraclePrice() expect(uint256);

    // Gate summaries: ghost-controlled
    function _.canIncreaseCredit(address) external => CVL_canIncreaseCredit() expect(bool);
    function _.canIncreaseDebt(address) external => CVL_canIncreaseDebt() expect(bool);
    function _.canLiquidate(address) external => CVL_canLiquidate() expect(bool);

    // Callback summaries: ghost-controlled
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => CVL_callbackBytes32() expect(bytes32);
    function _.onRepay(bytes32, Midnight.Obligation, uint256, address, bytes) external => CVL_callbackVoid() expect void;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => CVL_callbackVoid() expect void;
    function _.onFlashLoan(address, uint256, bytes) external => CVL_callbackVoid() expect void;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;

    // Token transfer summaries: ghost-controlled
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => CVL_safeTransferFrom();
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => CVL_safeTransfer();

    // Internal library summaries
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);
}

ghost CVL_msb(uint128) returns uint256;

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
// Persistent ghosts survive callback havocs, ensuring forced behavior persists through the entire transaction.

persistent ghost bool forceOracleRevert;

persistent ghost bool forceOracleReturnZero;

persistent ghost bool forceCanIncreaseCreditFalse;

persistent ghost bool forceCanIncreaseDebtFalse;

persistent ghost bool forceCanLiquidateFalse;

persistent ghost bool forceCallbackRevert;

persistent ghost bool forceCallbackBadReturn;

persistent ghost bool forceTransferRevert;

persistent ghost bool forceTransferFromRevert;

/// SUMMARIES ///

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    lastId = id;
    return id;
}

function CVL_oraclePrice() returns uint256 {
    if (forceOracleRevert) {
        revert();
    }
    if (forceOracleReturnZero) {
        return 0;
    }
    uint256 price;
    return price;
}

function CVL_canIncreaseCredit() returns bool {
    if (forceCanIncreaseCreditFalse) {
        bool shouldRevert;
        if (shouldRevert) {
            revert();
        }
        return false;
    }
    bool result;
    return result;
}

function CVL_canIncreaseDebt() returns bool {
    if (forceCanIncreaseDebtFalse) {
        bool shouldRevert;
        if (shouldRevert) {
            revert();
        }
        return false;
    }
    bool result;
    return result;
}

function CVL_canLiquidate() returns bool {
    if (forceCanLiquidateFalse) {
        bool shouldRevert;
        if (shouldRevert) {
            revert();
        }
        return false;
    }
    bool result;
    return result;
}

function CVL_callbackBytes32() returns bytes32 {
    if (forceCallbackRevert) {
        revert();
    }
    if (forceCallbackBadReturn) {
        bytes32 bad;
        require bad != to_bytes32(0xee60b2e8d46b15beabf6792dae952096e6cb7b86b90ca90f7c00aa15c812ff1a), "not CALLBACK_SUCCESS";
        return bad;
    }
    bytes32 result;
    return result;
}

function CVL_callbackVoid() {
    if (forceCallbackRevert) {
        revert();
    }
}

function CVL_safeTransferFrom() {
    if (forceTransferFromRevert) {
        revert();
    }
}

function CVL_safeTransfer() {
    if (forceTransferRevert) {
        revert();
    }
}

/// ORACLE REVERT PROPAGATION ///

/// If any activated collateral oracle reverts on price, liquidate reverts when the borrower has activated collaterals.
rule oracleRevertCausesLiquidateRevert(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require forceOracleRevert, "oracle reverts on price";

    bytes32 id;
    require activatedCollaterals(id, borrower) != 0, "borrower has activated collaterals";

    liquidate@withrevert(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId, "id derived from obligation";

    assert lastReverted;
}

/// If any activated collateral oracle reverts on price, withdrawCollateral reverts when the borrower has debt.
rule oracleRevertCausesWithdrawCollateralRevert(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    require forceOracleRevert, "oracle reverts on price";

    bytes32 id;
    require activatedCollaterals(id, onBehalf) != 0, "borrower has activated collaterals";

    withdrawCollateral@withrevert(e, obligation, collateralIndex, assets, onBehalf, receiver);
    bool reverted = lastReverted;

    require id == lastId, "id derived from obligation";

    assert debtOf(id, onBehalf) > 0 => reverted;
}

/// If any activated collateral oracle reverts on price, isHealthy reverts.
rule oracleRevertCausesIsHealthyRevert(env e, Midnight.Obligation obligation, bytes32 id, address borrower) {
    require forceOracleRevert, "oracle reverts on price";
    require activatedCollaterals(id, borrower) != 0, "borrower has activated collaterals";

    isHealthy@withrevert(e, obligation, id, borrower);
    bool reverted = lastReverted;

    require id == lastId, "id derived from obligation";

    assert debtOf(id, borrower) > 0 => reverted;
}

/// If all oracles revert and take succeeds, the seller must have no debt.
rule oracleRevertPreventsTakeWhenSellerHasDebt(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceOracleRevert, "oracle reverts on price";

    bytes32 id;
    address seller = offer.buy ? taker : offer.maker;
    require !liquidationLocked(id, seller), "seller is not liquidation locked";

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id derived from obligation";

    assert debtOf(id, seller) == 0;
}

/// ORACLE RETURNS ZERO ///

/// If the oracle returns 0, liquidate reverts when using repaid units as input.
rule oracleZeroCausesLiquidateWithRepaidRevert(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    require forceOracleReturnZero, "oracle returns zero";
    require repaidUnits > 0, "using repaid units as input";

    bytes32 id;
    require activatedCollaterals(id, borrower) != 0, "borrower has activated collaterals";

    liquidate@withrevert(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    require id == lastId, "id derived from obligation";

    assert lastReverted;
}

/// If the oracle returns 0 and the borrower has debt, isHealthy returns false.
rule oracleZeroCausesIsHealthyReturnFalse(env e, Midnight.Obligation obligation, bytes32 id, address borrower) {
    require forceOracleReturnZero, "oracle returns zero";
    require activatedCollaterals(id, borrower) != 0, "borrower has activated collaterals";

    bool healthy = isHealthy(e, obligation, id, borrower);

    require id == lastId, "id derived from obligation";

    assert debtOf(id, borrower) > 0 => !healthy;
}

/// If the oracle returns 0, withdrawCollateral reverts when the borrower has debt.
rule oracleZeroCausesWithdrawCollateralRevert(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    require forceOracleReturnZero, "oracle returns zero";

    bytes32 id;
    require activatedCollaterals(id, onBehalf) != 0, "borrower has activated collaterals";

    withdrawCollateral@withrevert(e, obligation, collateralIndex, assets, onBehalf, receiver);
    bool reverted = lastReverted;

    require id == lastId, "id derived from obligation";

    assert debtOf(id, onBehalf) > 0 => reverted;
}

/// If the oracle returns 0 and take succeeds, the seller must have no debt.
rule oracleZeroPreventsTakeWhenSellerHasDebt(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceOracleReturnZero, "oracle returns zero";

    bytes32 id;
    address seller = offer.buy ? taker : offer.maker;
    require !liquidationLocked(id, seller), "seller is not liquidation locked";

    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);
    bool reverted = lastReverted;

    require id == lastId, "id derived from obligation";

    assert debtOf(id, seller) > 0 => reverted;
}

/// GATE BLOCKING ///

/// If enterGate.canIncreaseCredit returns false and take succeeds, the buyer's credit does not increase.
rule enterGateBlocksCreditIncrease(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceCanIncreaseCreditFalse, "canIncreaseCredit blocked";
    require offer.obligation.enterGate != 0, "enter gate is set";

    bytes32 id;
    address buyer = offer.buy ? offer.maker : taker;
    uint256 creditBefore = creditOf(id, buyer);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id derived from obligation";
    uint256 creditAfter = creditOf(id, buyer);

    assert creditAfter <= creditBefore;
}

/// If enterGate.canIncreaseDebt returns false and take succeeds, the seller's debt does not increase.
rule enterGateBlocksDebtIncrease(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceCanIncreaseDebtFalse, "canIncreaseDebt blocked";
    require offer.obligation.enterGate != 0, "enter gate is set";

    bytes32 id;
    address seller = offer.buy ? taker : offer.maker;
    uint256 debtBefore = debtOf(id, seller);

    take(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    require id == lastId, "id derived from obligation";
    uint256 debtAfter = debtOf(id, seller);

    assert debtAfter <= debtBefore;
}

/// If the liquidator gate returns false on canLiquidate, liquidate reverts.
rule liquidatorGateBlocksLiquidation(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require forceCanLiquidateFalse, "canLiquidate blocked";
    require obligation.liquidatorGate != 0, "liquidator gate is set";

    liquidate@withrevert(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert lastReverted;
}

/// TOKEN TRANSFER REVERT PROPAGATION ///

/// If transferFrom reverts, take, repay, supplyCollateral, liquidate, and flashLoan all revert.
rule transferFromRevertPropagation(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, bytes, bytes32, bytes32[]).selector
        || f.selector == sig:repay(Midnight.Obligation, uint256, address, bytes).selector
        || f.selector == sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        || f.selector == sig:flashLoan(address, uint256, address, bytes).selector
} {
    require forceTransferFromRevert, "transferFrom reverts";
    f@withrevert(e, args);
    assert lastReverted;
}

/// If transfer reverts, withdraw, withdrawCollateral, fee claims, liquidate, and flashLoan all revert.
rule transferRevertPropagation(method f, env e, calldataarg args)
filtered {
    f -> f.selector == sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        || f.selector == sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
        || f.selector == sig:claimTradingFee(address, uint256, address).selector
        || f.selector == sig:claimContinuousFee(Midnight.Obligation, uint256, address).selector
        || f.selector == sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        || f.selector == sig:flashLoan(address, uint256, address, bytes).selector
} {
    require forceTransferRevert, "transfer reverts";
    f@withrevert(e, args);
    assert lastReverted;
}

/// CALLBACK REVERT PROPAGATION ///

/// If the callback reverts, callback-enabled take (with non-zero taker callback) reverts.
rule callbackRevertCausesTakeRevert(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceCallbackRevert, "callback reverts";
    require takerCallback != 0, "callback-enabled take";

    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert lastReverted;
}

/// If the callback reverts, callback-enabled repay (with non-empty data) reverts.
rule callbackRevertCausesRepayRevert(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) {
    require forceCallbackRevert, "callback reverts";
    require data.length > 0, "callback-enabled repay";

    repay@withrevert(e, obligation, units, onBehalf, data);

    assert lastReverted;
}

/// If the callback reverts, callback-enabled liquidate (with non-empty data) reverts.
rule callbackRevertCausesLiquidateRevert(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    require forceCallbackRevert, "callback reverts";
    require data.length > 0, "callback-enabled liquidate";

    liquidate@withrevert(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert lastReverted;
}

/// If the callback reverts, flashLoan reverts.
rule callbackRevertCausesFlashLoanRevert(env e, address token, uint256 assets, address callback, bytes data) {
    require forceCallbackRevert, "callback reverts";

    flashLoan@withrevert(e, token, assets, callback, data);

    assert lastReverted;
}

/// If a buy/sell callback returns something other than CALLBACK_SUCCESS, callback-enabled take reverts.
rule callbackBadReturnCausesTakeRevert(env e, uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) {
    require forceCallbackBadReturn, "callback returns bad value";
    require takerCallback != 0, "callback-enabled take";

    take@withrevert(e, units, taker, takerCallback, takerCallbackData, receiver, offer, ratifierData, root, proof);

    assert lastReverted;
}
