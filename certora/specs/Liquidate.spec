// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint128) envfree;
    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function collateral(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;

    // Oracle summary: we assume the price does not change during the execution of a transaction.
    function _.price() external => PER_CALLEE_CONSTANT;

    // UtilsLib summaries: msb, mulDivDown, and mulDivUp are deterministic.
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => summaryMsb(bitmap);
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => summaryMulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => summaryMulDivUp(a, b, denominator);

    // IdLib summary: remember the last id returned by toId.
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(market, chainId, midnight);
}

/// HELPERS ///

persistent ghost bytes32 liqId;

function summaryToId(Midnight.Market market, uint256 chainId, address midnight) returns bytes32 {
    bytes32 id;
    liqId = id;
    return id;
}

ghost summaryMsb(uint128) returns uint256;

ghost summaryMulDivDown(uint256, uint256, uint256) returns uint256;

ghost summaryMulDivUp(uint256, uint256, uint256) returns uint256;

ghost summaryPrice(address) returns uint256;

// RULES ///

/// Credit does not change on liquidate. Debt and collateral of a user can only change via liquidate if the position is liquidatable and user is borrower.
/// Furthermore, liquidate can only decrease the borrower's debt and collateral (w.r.t the collateralIndex passed in liquidate).
/// Also show that liquidate can only be called on liquidatable positions.
rule liquidateOnlyAffectsBalancesWhenLiquidatable(env e, Midnight.Market market, uint256 liqIndex, uint256 seizedAssets, uint256 repaidUnits, address liqUser, address receiver, address callback, bytes data, bool postMaturityMode) {
    bytes32 id;
    address user;
    uint256 collateralIndex;

    bool wasLiquidatable = debtOf(id, liqUser) > 0 && !liquidationLocked(id, liqUser) && (e.block.timestamp > market.maturity || !isHealthy(market, id, liqUser));

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    uint256 collateralBefore = collateral(id, user, collateralIndex);

    liquidate(e, market, liqIndex, seizedAssets, repaidUnits, liqUser, postMaturityMode, receiver, callback, data);

    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);
    uint256 collateralAfter = collateral(id, user, collateralIndex);

    assert id == liqId => wasLiquidatable;
    assert creditAfter == creditBefore;
    assert debtAfter == debtBefore || (id == liqId && user == liqUser);
    assert collateralAfter == collateralBefore || (id == liqId && user == liqUser && collateralIndex == liqIndex);
    assert debtAfter <= debtBefore;
    assert collateralAfter <= collateralBefore;
}
