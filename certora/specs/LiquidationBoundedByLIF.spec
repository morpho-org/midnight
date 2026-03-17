// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic toId summary using a ghost that takes simple types (no struct).
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryObligationId(obligation.loanToken, obligation.maturity);

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryObligationId(address, uint256) returns bytes32;

/// LIF BOUNDARIES ///

/// Liquidation profit is bounded by maxLif (repaidUnits input)
rule liquidationProfitBoundedInputRepaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert repaidUnits > 0 => seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBoundedSeizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require data.length == 0, "no callback for prover performance";
    require maxLif >= WAD(), "maxLif must be at least 1x for profit boundedness";

    bytes32 id0 = summaryObligationId(obligation.loanToken, obligation.maturity);
    require to_mathint(currentContract.borrowerState[id0][borrower].activatedCollaterals) == 2 ^ to_mathint(collateralIndex), "exactly 1 active collateral at collateralIndex so the loop sets liquidatedCollatPrice";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert seizedAssets > 0 => seizedResult * price * WAD() <= repaidResult * ORACLE_PRICE_SCALE() * maxLif;
}
