// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as midnight;

methods {
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function midnight.debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function midnight.isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function midnight.tickSpacing(bytes32 id) external returns (uint8) envfree;

    // Deterministic market id (same pattern as Midnight.spec / TakeAmountsLibInvertibility.spec).
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);

    // Deterministic floor division; must not call MulDiv (it delegates back to UtilsLib.mulDivDown).
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);

    // Token / permit functions are irrelevant to the units formula but NONDET prevent havoc calls.
    function _.allowance(address, address) external => NONDET;
    function _.approve(address, uint256) external => NONDET;
    function _.permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    if (d == 0) {
        revert();
    }
    return require_uint256((to_mathint(a) * to_mathint(b)) / to_mathint(d));
}

definition WAD() returns uint256 = 10 ^ 18;

// assets = floor(D * W / (W - p)), r = floor(assets * p / W), units = assets - r.
// Show units = D for all D > 0 and 0 <= p < W (bundler requires p < W).
rule repayUnitsFormula(uint256 D, uint256 referralFeePct) {
    require referralFeePct < WAD(), "PctExceeded: bundler reverts otherwise";

    uint256 wMinusP = assert_uint256(WAD() - referralFeePct);
    uint256 assets = summaryMulDivDown(D, WAD(), wMinusP);
    uint256 r = summaryMulDivDown(assets, referralFeePct, WAD());
    uint256 units = assert_uint256(assets - r);

    assert units == D;
}

// End-to-end: for any target units U <= debtBefore, calling repayAndWithdrawCollateral
// with assets = floor(U * WAD / (WAD - pct)) repays exactly U units on Midnight.
// Composes with repayUnitsFormula: assets - floor(assets*pct/WAD) == U, hence debt decreases by U.
rule repayAndWithdrawCollateralRepaysTargetUnits(env e, Midnight.Market market, address onBehalf, address collateralReceiver, address referralFeeRecipient, uint256 referralFeePct, uint256 U) {
    require referralFeePct < WAD(), "PctExceeded";

    bytes32 id = summaryToId(market);
    uint256 debtBefore = midnight.debtOf(id, onBehalf);
    require U > 0 && U <= debtBefore, "target units within current debt";

    require midnight.isAuthorized(onBehalf, currentContract), "bundler must be authorized on Midnight for repay";

    uint256 wMinusP = assert_uint256(WAD() - referralFeePct);
    uint256 assets = summaryMulDivDown(U, WAD(), wMinusP);

    MidnightBundles.TokenPermit loanTokenPermit;

    // PermitKind.None — avoid ERC2612 / Permit2 paths (irrelevant to units, havoc external calls).
    require assert_uint8(loanTokenPermit.kind) == 0, "PermitKind.None == 0.";

    MidnightBundles.CollateralWithdrawal[] collateralWithdrawals;
    require collateralWithdrawals.length == 0, "isolate repay path from withdrawals";

    repayAndWithdrawCollateral(e, market, assets, onBehalf, loanTokenPermit, collateralWithdrawals, collateralReceiver, referralFeePct, referralFeeRecipient);

    assert midnight.debtOf(id, onBehalf) == debtBefore - U;
}
