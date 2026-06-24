// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;
using Midnight as midnight;

methods {
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;
    function midnight.debt(bytes32 id, address user) external returns (uint128) envfree;
    function midnight.isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
    function midnight.tickSpacing(bytes32 id) external returns (uint8) envfree;

    // Deterministic market id (same pattern as Midnight.spec / TakeAmountsLibInvertibility.spec).
    function IdLib.toId(Midnight.Market memory market) internal returns (bytes32) => summaryToId(market);

    // Deterministic mulDivDown.
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);

    // Token / permit functions are irrelevant to the units formula, use a NONDET summary to prevent calls that havoc Midnight.
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
    if (d == 0 || a * b > max_uint256) {
        revert();
    }
    mathint result = a * b / d;
    assert result >= 0 && result <= 2 ^ 256;
    return require_uint256(result);
}

definition WAD() returns uint256 = 10 ^ 18;

// End-to-end: for any target units U <= debtBefore, calling repayAndWithdrawCollateral
// with assets = floor(U * WAD / (WAD - pct)) repays exactly U units on Midnight.
rule repayAndWithdrawCollateralRepaysTargetUnits(env e, Midnight.Market market, address onBehalf, address collateralReceiver, address referralFeeRecipient, uint256 referralFeePct, uint256 U) {
    require referralFeePct < WAD(), "PctExceeded";

    bytes32 id = summaryToId(market);
    uint256 debtBefore = midnight.debt(id, onBehalf);

    uint256 wMinusP = assert_uint256(WAD() - referralFeePct);
    uint256 assets = summaryMulDivDown(U, WAD(), wMinusP);

    MidnightBundles.TokenPermit loanTokenPermit;

    require assert_uint8(loanTokenPermit.kind) == 0, "ignore irrelevant Permit2 and ERC2612 paths to avoid summarizing external calls";

    MidnightBundles.CollateralWithdrawal[] collateralWithdrawals;
    require collateralWithdrawals.length == 0, "isolate repay path from withdrawals";

    repayAndWithdrawCollateral(e, market, assets, onBehalf, loanTokenPermit, collateralWithdrawals, collateralReceiver, referralFeePct, referralFeeRecipient);

    assert midnight.debt(id, onBehalf) == debtBefore - U;
}
