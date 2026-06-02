// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function collateralBitmap(bytes32 id, address user) external returns (uint128) envfree;
    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function totalUnits(bytes32 id) external returns (uint128) envfree;
    function withdrawable(bytes32 id) external returns (uint128) envfree;
    function normalModeMaxLiquidationPreview(Midnight.Market, bytes32, uint256, address) external returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256, uint256) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Oracle prices are deterministic for each oracle during a rule.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic market id and no market-creation side effects in this focused proof.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);
    function touchMarket(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Token transfers are external liveness assumptions here; balance/approval failure is covered by revert specs.
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Match the arithmetic summaries used by the existing liquidation specs.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 d) internal returns (uint256) => summaryMulDivDown(a, b, d);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 d) internal returns (uint256) => summaryMulDivUp(a, b, d);
}

/// HELPERS ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

// Axioms proved in MulDiv.spec and reused by liquidation specs.
persistent ghost ghostMulDivDown(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivDown(a, b, d) * d <= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => (ghostMulDivDown(a, b, d) + 1) * d > a * b;
}

persistent ghost ghostMulDivUp(uint256, uint256, uint256) returns uint256 {
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 => ghostMulDivUp(a, b, d) * d >= a * b;
    axiom forall uint256 a. forall uint256 b. forall uint256 d. d > 0 && ghostMulDivUp(a, b, d) > 0 => (ghostMulDivUp(a, b, d) - 1) * d < a * b;
}

function summaryToId(Midnight.Market market) returns bytes32 {
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].lltv <= WAD(), "valid market: lltv <= WAD";
    require forall uint256 i. i < market.collateralParams.length => market.collateralParams[i].maxLif >= WAD() && market.collateralParams[i].maxLif <= 2 * WAD(), "valid market: WAD <= maxLif <= 2 WAD";
    return Utils.hashMarket(market);
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivDown(a, b, d);
}

function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return ghostMulDivUp(a, b, d);
}

function requireRequestedFormulaSetup(env e, Midnight.Market market, bytes32 id, uint256 collateralIndex, address borrower, uint256 previewSeized, uint256 previewRepaid, uint256 maxDebt, uint256 badDebt, uint256 debtAfterBadDebt, uint256 liquidatedCollatPrice, uint256 collateralBefore, uint256 maxRepaid, bool rcfThresholdBypassed, uint256 fullSeizeRepaid, uint256 repayInputSeized) {
    require e.block.timestamp <= market.maturity, "pre-maturity: post-maturity mode cannot bypass normal-mode recovery";
    require market.liquidatorGate == 0, "no liquidator gate";
    require collateralIndex < market.collateralParams.length, "valid collateral index";
    require collateralIndex < 128, "bitmap-compatible collateral index";
    require market.collateralParams[collateralIndex].lltv == WAD() || to_mathint(market.collateralParams[collateralIndex].maxLif) * market.collateralParams[collateralIndex].lltv < WAD() * WAD(), "valid normal-mode RCF denominator";

    uint128 bitmap = collateralBitmap(id, borrower);
    require summaryGetBit(bitmap, collateralIndex), "selected collateral is active";
    require summaryCountBits(bitmap) <= 2, "bounded active collateral count for loop unrolling";

    require debtOf(id, borrower) > 0, "borrower has debt";
    require debtOf(id, borrower) > maxDebt, "borrower is normal-mode liquidatable";
    require !liquidationLocked(id, borrower), "liquidation not locked";
    require collateralBefore == collateral(id, borrower, collateralIndex), "preview collateral matches getter";
    require collateralBefore > 0, "selected collateral is nonzero";
    require liquidatedCollatPrice == summaryPrice(market.collateralParams[collateralIndex].oracle), "preview price matches oracle summary";
    require liquidatedCollatPrice > 0, "selected collateral price is nonzero";
    require badDebt <= debtOf(id, borrower), "bad debt is bounded by debt";
    require debtAfterBadDebt == debtOf(id, borrower) - badDebt, "debt after bad debt matches prestate";
    require badDebt == 0 || (totalUnits(id) > 0 && totalUnits(id) >= badDebt), "market can realize bad debt";
    require to_mathint(withdrawable(id)) + previewRepaid <= max_uint128, "withdrawable can increase by repayment";

    require previewSeized > 0 || previewRepaid > 0, "candidate is a nonzero liquidation";
    require previewSeized == 0 || previewRepaid == 0, "candidate uses exactly one input mode";
    require previewSeized <= max_uint128, "seized assets fit position collateral type";
    require previewRepaid <= max_uint128, "repaid units fit position debt type";

    // The requested selector is not executable in states where full seizure would over-repay debt or repayment input
    // would over-seize collateral. These fit requirements are necessary because the selector intentionally does not
    // include those caps; without them there are concrete counterexamples.
    require rcfThresholdBypassed => previewSeized == collateralBefore && fullSeizeRepaid <= debtAfterBadDebt, "full-seize branch fits debt";
    require !rcfThresholdBypassed => previewRepaid == (maxRepaid < debtAfterBadDebt ? maxRepaid : debtAfterBadDebt) && repayInputSeized <= collateralBefore, "repay branch fits collateral";
}

/// RULES ///

/// The requested normal-mode max liquidation input succeeds under the explicit fit assumptions above.
rule requestedMaxNormalModeLiquidationSucceeds(env e, Midnight.Market market, uint256 collateralIndex, address borrower, address receiver, bytes data) {
    require data.length == 0, "no callback data";
    address callback = 0;
    bytes32 id = summaryToId(market);

    uint256 previewSeized;
    uint256 previewRepaid;
    uint256 maxDebt;
    uint256 badDebt;
    uint256 debtAfterBadDebt;
    uint256 liquidatedCollatPrice;
    uint256 collateralBefore;
    uint256 maxRepaid;
    bool rcfThresholdBypassed;
    uint256 fullSeizeRepaid;
    uint256 repayInputSeized;
    previewSeized, previewRepaid, maxDebt, badDebt, debtAfterBadDebt, liquidatedCollatPrice, collateralBefore, maxRepaid, rcfThresholdBypassed, fullSeizeRepaid, repayInputSeized = normalModeMaxLiquidationPreview(market, id, collateralIndex, borrower);

    requireRequestedFormulaSetup(e, market, id, collateralIndex, borrower, previewSeized, previewRepaid, maxDebt, badDebt, debtAfterBadDebt, liquidatedCollatPrice, collateralBefore, maxRepaid, rcfThresholdBypassed, fullSeizeRepaid, repayInputSeized);

    liquidate@withrevert(e, market, collateralIndex, previewSeized, previewRepaid, borrower, false, receiver, callback, data);

    assert !lastReverted;
}

/// After the requested max liquidation succeeds, any further nonzero normal-mode liquidation on the same collateral reverts.
rule requestedMaxNormalModeLiquidationBlocksFurtherSameCollateral(env e, Midnight.Market market, uint256 collateralIndex, address borrower, address receiver, address secondReceiver, uint256 secondSeized, uint256 secondRepaid, bytes data) {
    require data.length == 0, "no callback data";
    address callback = 0;
    bytes32 id = summaryToId(market);

    uint256 previewSeized;
    uint256 previewRepaid;
    uint256 maxDebt;
    uint256 badDebt;
    uint256 debtAfterBadDebt;
    uint256 liquidatedCollatPrice;
    uint256 collateralBefore;
    uint256 maxRepaid;
    bool rcfThresholdBypassed;
    uint256 fullSeizeRepaid;
    uint256 repayInputSeized;
    previewSeized, previewRepaid, maxDebt, badDebt, debtAfterBadDebt, liquidatedCollatPrice, collateralBefore, maxRepaid, rcfThresholdBypassed, fullSeizeRepaid, repayInputSeized = normalModeMaxLiquidationPreview(market, id, collateralIndex, borrower);

    requireRequestedFormulaSetup(e, market, id, collateralIndex, borrower, previewSeized, previewRepaid, maxDebt, badDebt, debtAfterBadDebt, liquidatedCollatPrice, collateralBefore, maxRepaid, rcfThresholdBypassed, fullSeizeRepaid, repayInputSeized);

    liquidate@withrevert(e, market, collateralIndex, previewSeized, previewRepaid, borrower, false, receiver, callback, data);
    assert !lastReverted, "first max liquidation succeeds";
    require !lastReverted, "continue from successful first liquidation";

    require secondSeized == 0 || secondRepaid == 0, "second liquidation uses at most one input mode";
    require secondSeized > 0 || secondRepaid > 0, "second liquidation is nonzero";

    liquidate@withrevert(e, market, collateralIndex, secondSeized, secondRepaid, borrower, false, secondReceiver, callback, data);

    assert lastReverted;
}
