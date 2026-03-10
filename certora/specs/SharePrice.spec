// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

// Check the ratio of units over shares is below or equal to 1.
strong invariant sharePriceBelowOrEqOne(bytes32 id)
    totalShares(id) >= totalUnits(id);

/// Liquidation does not change the total shares.
rule liquidateDoesNotChangeShares(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    mathint sharesBefore = totalShares(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalShares(id) == sharesBefore;
}

/// Liquidation does not increase the total units.
rule liquidateDoesNotIncreaseUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    mathint unitsBefore = totalUnits(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalUnits(id) <= unitsBefore;
}

/// Virtual share price = (totalUnits+1)/(totalShares+1) monotonicity.
/// Liquidation is excluded: it can decrease the share price via bad debt socialization but covered above.
rule sharePriceDoesNotDecrease(bytes32 id, method f) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && !f.isView } {
    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    env e;
    calldataarg args;
    f(e, args);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    assert (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}
