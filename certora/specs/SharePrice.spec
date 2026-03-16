// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function sharePrice(bytes32 id) external returns (uint256) envfree;

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

// Share price is at most SHARE_PRICE_SCALE (type(uint128).max).
strong invariant sharePriceBelowOrEqScale(bytes32 id)
    sharePrice(id) <= max_uint128;

/// Liquidation does not increase the share price.
rule liquidateDoesNotIncreaseSharePrice(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    mathint sharePriceBefore = sharePrice(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert sharePrice(id) <= sharePriceBefore;
}

/// Liquidation does not increase the total units.
rule liquidateDoesNotIncreaseUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    mathint unitsBefore = totalUnits(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalUnits(id) <= unitsBefore;
}

/// Share price monotonicity: share price does not decrease for non-liquidation functions.
/// Liquidation is excluded: it can decrease the share price via bad debt socialization but covered above.
rule sharePriceDoesNotDecrease(bytes32 id, method f) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && !f.isView } {
    mathint sharePriceBefore = sharePrice(id);

    env e;
    calldataarg args;
    f(e, args);

    assert sharePrice(id) >= sharePriceBefore;
}
