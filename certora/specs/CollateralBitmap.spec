// SPDX-License-Identifier: GPL-2.0-or-later

import "BitmapSummaries.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateral(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function isHealthy(Midnight.Market, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Market, bytes32, address) external returns (bool) envfree;

    /* Assumption: price does not change during rules.
     * We want to show that isHealthy() and isHealthyNoBitmap() behaves the same under the
     * assumption that each function uses the same oracle price for the corresponding collateral.
     */
    function _.price() external => PER_CALLEE_CONSTANT;
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Market memory market, uint256 chainId, address midnight) internal returns (bytes32) => NONDET;

    /* Simplify mulDiv reasoning for the solver.  We summarize these by ghost functions, i.e.,
     * arbitrary deterministic functions and axiomatize the axioms we need.
     */
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARY ///

definition MAX_COLLATERALS_PER_BORROWER() returns uint256 = 10;

persistent ghost summaryMulDivDown(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDown(0, b, d) == 0;
}

persistent ghost summaryMulDivUp(uint256, uint256, uint256) returns uint256;

// Check that a collateral bit is set exactly when there is collateral for that index.
strong invariant nonZeroCollateralsAreActivated(bytes32 id, address user, uint256 collateralIndex)
    collateralIndex < 128 => (collateral(id, user, collateralIndex) != 0 <=> summaryGetBit(currentContract.position[id][user].collateralBitmap, collateralIndex));

// Check that the number of activated collaterals never exceeds MAX_COLLATERALS_PER_BORROWER.
// This bounds the while-loop iterations in isHealthy() and liquidate().
strong invariant atMostMaxCollateralsBitsSet(bytes32 id, address user)
    summaryCountBits(currentContract.position[id][user].collateralBitmap) <= MAX_COLLATERALS_PER_BORROWER();

// This shows that the real isHealthy returns true if and only if the isHealthy function
// that does not use collateral bitmap returns true.  We also check that the latter function
// does not revert if isHealthy does not revert.
rule isHealthyEquivalent(Midnight.Market market, bytes32 id, address borrower) {
    require market.collateralParams.length <= 3, "restrict to three collateralParams";
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 0);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 1);
    requireInvariant nonZeroCollateralsAreActivated(id, borrower, 2);

    // We make no claim about isHealthyNoBitmap() if isHealthy() reverts.
    bool isHealthy1 = isHealthy(market, id, borrower);
    bool isHealthy2 = isHealthyNoBitmap@withrevert(market, id, borrower);

    // Assert that isHealthyNoBitmap() does not revert and returns the same value.
    assert !lastReverted;
    assert isHealthy1 == isHealthy2;
}
