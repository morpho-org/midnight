// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function sharePrice(bytes32 id) external returns (uint256) envfree;
    function obligationCreated(bytes32 id) external returns (bool) envfree;

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

    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
}

/// Liquidation does not increase the share price. Trivially true from the min formula.
rule liquidateDoesNotIncreaseSharePrice(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require obligationCreated(id);
    mathint sharePriceBefore = sharePrice(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert sharePrice(id) <= sharePriceBefore;
}

/// Liquidation does not increase the total units of an already-created obligation.
rule liquidateDoesNotIncreaseUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require obligationCreated(id);
    mathint unitsBefore = totalUnits(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalUnits(id) <= unitsBefore;
}

/// After liquidation with bad debt, sharePrice is calibrated: sharePrice * totalShares <= totalUnits * SCALE.
/// Only asserted when sharePrice actually changed (recalibration occurred), avoiding the free-id problem
/// where a different obligation's drifted state would need an unsound precondition.
rule liquidateSharePriceCalibrated(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require obligationCreated(id);
    mathint sharePriceBefore = sharePrice(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert sharePrice(id) != sharePriceBefore => to_mathint(sharePrice(id)) * to_mathint(totalShares(id)) <= to_mathint(totalUnits(id)) * to_mathint(max_uint128);
}

/// sharePrice is unchanged by any function other than liquidate (which can only decrease it).
rule sharePriceUnchangedOutsideLiquidate(bytes32 id, method f) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && !f.isView } {
    require obligationCreated(id);
    mathint sharePriceBefore = sharePrice(id);

    env e;
    calldataarg args;
    f(e, args);

    assert sharePrice(id) == sharePriceBefore;
}
