// SPDX-License-Identifier: GPL-2.0-or-later

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Summary to capture the oracle price so the spec can reference it in assertions.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic toId summary so the rule and the contract resolve to the same obligation id.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation);

    function Utils.hashObligation(Midnight.Obligation) external returns (bytes32) envfree;
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

function summaryToId(Midnight.Obligation obligation) returns bytes32 {
    return Utils.hashObligation(obligation);
}

/// LIF BOUNDARIES ///

/// Liquidation profit is bounded by maxLif (repaidUnits input)
rule liquidationProfitBoundedInputRepaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require repaidUnits > 0, "repaidUnits must be positive";
    require data.length == 0, "no callback for prover performance";

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert maxLif >= WAD() => to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBounded_seizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require seizedAssets > 0, "seizedAssets must be positive";
    require data.length == 0, "no callback for prover performance";

    // Restrict to 1 active collateral so the loop processes collateralIndex and sets liquidatedCollatPrice.
    bytes32 id0 = summaryToId(obligation);
    require to_mathint(currentContract.borrowerState[id0][borrower].activatedCollaterals) == 2 ^ to_mathint(collateralIndex);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert maxLif >= WAD() => to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}
