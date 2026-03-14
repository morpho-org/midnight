// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Assume price doesn't change during the execution of a transaction.
    function _.price() external => summaryPrice(calledContract) expect(uint256);

    // Deterministic toId summary so the rule and the contract resolve to the same obligation id.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => summaryToId(obligation);
}

/// SUMMARIES ///

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryObligationId(address, uint256) returns bytes32;

function summaryToId(Midnight.Obligation obligation) returns bytes32 {
    return summaryObligationId(obligation.loanToken, obligation.maturity);
}

/// LIF BOUNDARIES ///

/// Liquidation profit is bounded by maxLif (repaidUnits input)
rule liquidationProfitBounded_repaidUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 repaidUnits, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require maxLif >= WAD();
    require repaidUnits > 0;

    // Safe: seized/repaid amounts are computed before the callback; data.length == 0 skips it for prover performance.
    require data.length == 0;

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, 0, repaidUnits, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}

/// Liquidation profit is bounded by maxLif (seizedAssets input)
rule liquidationProfitBounded_seizedAssets(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, address borrower, bytes data) {
    mathint maxLif = obligation.collaterals[collateralIndex].maxLif;
    require maxLif >= WAD();
    require seizedAssets > 0;

    // Safe: seized/repaid amounts are computed before the callback; data.length == 0 skips it for prover performance.
    require data.length == 0;

    // The while loop over activatedCollaterals is unrolled optimistically (loop_iter: 2).
    // Restrict to 1 active collateral so the loop processes collateralIndex and sets liquidatedCollatPrice.
    bytes32 id0 = summaryObligationId(obligation.loanToken, obligation.maturity);
    require to_mathint(currentContract.borrowerState[id0][borrower].activatedCollaterals) == 2 ^ to_mathint(collateralIndex);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, 0, borrower, data);

    mathint price = summaryPrice(obligation.collaterals[collateralIndex].oracle);

    assert to_mathint(seizedResult) * price * WAD() <= to_mathint(repaidResult) * ORACLE_PRICE_SCALE() * maxLif;
}
