// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Standalone discharge of axiomMaxDebtDrop assumed in MaxRepaidHealthy.spec: the Rocq lemma
// max_debt_contribution_drop_bound (rocq/maxRepaidHealthy.v:162), proven over concrete mulDivDown/mulDivUp
// (NOT summarized). Isolated in its own spec/conf so a hard-nonlinear timeout cannot gate the fast MulDiv leg.

methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// The LLTV-weighted maxDebt contribution drops by at most ceil(maxRepaid * lif * lltv / WAD^2) when seized is
// the L692 seizedAssets = floor(floor(maxRepaid * lif / WAD) * OPS / price). See rocq/maxRepaidHealthy.v:162.
rule maxDebtContributionDropBound(uint256 collat, uint256 price, uint256 lltv, uint256 maxRepaid, uint256 lif) {
    require price > 0, "0 < price";
    require lltv <= WAD(), "enabled lltv <= WAD";
    require lif <= 2 * WAD(), "maxLif <= 2 * WAD (see Midnight.sol:810)";

    uint256 maxSeizedValue = mulDivDown(maxRepaid, lif, WAD());
    uint256 seized = mulDivDown(maxSeizedValue, ORACLE_PRICE_SCALE(), price);
    require seized <= collat, "seized <= collateral (else liquidate reverts)";

    uint256 curContrib = mulDivDown(mulDivDown(collat, price, ORACLE_PRICE_SCALE()), lltv, WAD());
    uint256 newContrib = mulDivDown(mulDivDown(assert_uint256(collat - seized), price, ORACLE_PRICE_SCALE()), lltv, WAD());

    assert curContrib - newContrib <= mulDivUp(maxRepaid, require_uint256(lif * lltv), WAD() * WAD());
}
