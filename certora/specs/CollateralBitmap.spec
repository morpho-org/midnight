// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isLiquidatable(Midnight.Obligation, bytes32, address, uint256) external returns (bool, uint256, uint256, uint256) envfree;
    function isLiquidatableNoBitmap(Midnight.Obligation, bytes32, address, uint256) external returns (bool, uint256, uint256, uint256) envfree;

    /* Assumption: price does not change during rules.
     * We want to show that isLiquidatable() and isLiquidatableNoBitmap() behaves the same under the
     * assumption that each function uses the same oracle price for the corresponding collateral.
     */
    function _.price() external => PER_CALLEE_CONSTANT;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes32) => NONDET;

    /* Simplify mulDiv reasoning for the solver.  We summarize these by ghost functions, i.e.,
     * arbitrary deterministic functions and axiomatize the axioms we need.
     */
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARY ///

persistent ghost summaryMulDivDown(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDown(0, b, d) == 0;
}

persistent ghost summaryMulDivUp(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivUp(0, b, d) == 0;
}

// Check that a collateral bit is set exactly when there is collateral for that index.
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].activatedCollaterals, collateralIndex));

// This shows that isLiquidatable and isLiquidatableNoBitmap return the same values.
// We also check that the latter function does not revert if isLiquidatable does not revert.
rule isLiquidatableEquivalent(Midnight.Obligation obligation, bytes32 id, address borrower, uint256 collateralIndex) {
    require obligation.collateralParams.length <= 3, "restrict to three collateralParams";
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 2);

    bool isLiquidatable1;
    uint256 maxDebt1;
    uint256 collatPrice1;
    uint256 badDebt1;
    isLiquidatable1, maxDebt1, collatPrice1, badDebt1 = isLiquidatable(obligation, id, borrower, collateralIndex);
    bool isLiquidatable2;
    uint256 maxDebt2;
    uint256 collatPrice2;
    uint256 badDebt2;
    isLiquidatable2, maxDebt2, collatPrice2, badDebt2 = isLiquidatableNoBitmap@withrevert(obligation, id, borrower, collateralIndex);

    // Assert that isLiquidatableNoBitmap() does not revert and returns the same values.
    assert !lastReverted;
    assert isLiquidatable1 == isLiquidatable2;
    assert maxDebt1 == maxDebt2;
    assert collatPrice1 == collatPrice2;
    assert badDebt1 == badDebt2;
}
