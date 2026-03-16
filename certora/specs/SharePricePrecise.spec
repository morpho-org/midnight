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

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    require to_mathint(res) * to_mathint(d) <= to_mathint(x) * to_mathint(y);
    require (to_mathint(res) + 1) * to_mathint(d) > to_mathint(x) * to_mathint(y);
    return res;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    require to_mathint(res) * to_mathint(d) >= to_mathint(x) * to_mathint(y);
    require to_mathint(res) == 0 || (to_mathint(res) - 1) * to_mathint(d) < to_mathint(x) * to_mathint(y);
    return res;
}

/// Liquidation does not increase the share price. Trivially true from the min formula.
rule liquidateDoesNotIncreaseSharePrice(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require obligationCreated(id);
    mathint sharePriceBefore = sharePrice(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert sharePrice(id) <= sharePriceBefore;
}

/// After liquidation with bad debt, sharePrice is calibrated: sharePrice * totalShares <= totalUnits * SCALE.
rule liquidateSharePriceCalibrated(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require obligationCreated(id);
    mathint sharePriceBefore = sharePrice(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert sharePrice(id) != sharePriceBefore => to_mathint(sharePrice(id)) * to_mathint(totalShares(id)) <= to_mathint(totalUnits(id)) * to_mathint(max_uint128);
}
