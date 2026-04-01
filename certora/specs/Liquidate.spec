// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => CVL_price(calledContract) expect(uint256);
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);
    function UtilsLib.msb(uint128 bitmap) internal returns (uint256) => CVL_msb(bitmap);
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function Utils.passiveFeeRecipient() external returns (address) envfree;
    function _.canLiquidate(address) external => NONDET;
}

/// HELPERS ///

// IdLib summary: remember the last id returned by toId.

persistent ghost bytes32 lastId;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    // non-deterministic id
    bytes32 id;
    lastId = id;
    return id;
}

// UtilsLib summaries: msb, mulDivDown, and mulDivUp are deterministic

ghost CVL_msb(uint128) returns uint256;

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

// Oracle summary: we assume the price does not change during the execution of a transaction.

ghost CVL_price(address) returns uint256;

// RULES ///

/// Credit, debt, and collateral of a user can only change via liquidate if the position is liquidatable and user is borrower.
/// Furthermore, liquidate can only decrease the borrower's debt and collateral (w.r.t the collateralIndex passed in liquidate).
rule liquidateOnlyAffectsBalancesWhenLiquidatable(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, address user) {
    bytes32 id;
    bool liquidatable = !isHealthy(e, obligation, id, borrower) || obligation.maturity < e.block.timestamp;

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    uint256 collateralBefore = collateralOf(id, user, collateralIndex);
    uint256 borrowerDebtBefore = debtOf(id, borrower);
    uint256 borrowerCollateralBefore = collateralOf(id, borrower, collateralIndex);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    require id == lastId;

    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);
    uint256 collateralAfter = collateralOf(id, user, collateralIndex);
    uint256 borrowerDebtAfter = debtOf(id, borrower);
    uint256 borrowerCollateralAfter = collateralOf(id, borrower, collateralIndex);

    assert creditAfter == creditBefore || user == Utils.passiveFeeRecipient();
    assert debtAfter == debtBefore || (user == borrower && liquidatable);
    assert collateralAfter == collateralBefore || (user == borrower && liquidatable);
    assert borrowerDebtAfter <= borrowerDebtBefore;
    assert borrowerCollateralAfter <= borrowerCollateralBefore;
}

rule liquidateRequireUnhealthy(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id;
    bool isHealthyBefore = isHealthy(e, obligation, id, borrower);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    // it's okay to check only after the call that the prover chose the correct id.
    require id == lastId, "id should be derived from obligation";

    assert !isHealthyBefore || e.block.timestamp > obligation.maturity, "liquidate can only be called on unhealthy obligations";
}
