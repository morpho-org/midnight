// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// Standalone discharge of axiomMaxDebtDrop assumed in MaxRepaidHealthy.spec: the Rocq lemma
// max_debt_contribution_drop_bound (rocq/maxRepaidHealthy.v:162), proven over concrete mulDivDown/mulDivUp.
//
// A single monolithic assert of the full bound (5-nested divisions in one NIA query) times out at 2h. Instead we
// mirror the Rocq proof's decomposition (rocq/maxRepaidHealthy.v:75-247): each nested-mulDiv fact is proven as its
// own SMALL concrete rule (<= 2 nested divisions, so the solver closes it fast), and a final composition rule
// (maxDebtContributionDropBound) assembles them over UNINTERPRETED (ghost) mulDiv with only linear/NIA glue -- so
// the SMT never faces the nested-division goal in one query. This is the assume-ghost / prove-concrete split used
// by RealizableBadDebtLiquidate.spec + MulDiv.spec in PR #1079. Isolated in its own spec/conf so a hard-nonlinear
// timeout cannot gate the fast MulDiv leg.

methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
}

definition WAD() returns uint256 = 10 ^ 18;

definition ORACLE_PRICE_SCALE() returns uint256 = 10 ^ 36;

// Uninterpreted mulDiv, used ONLY by the composition rule so its goal stays linear (no nested division). Each
// assumed instance below is discharged by one of the concrete sub-lemma rules further down, over the real
// mulDivDown/mulDivUp of MulDiv.sol.
persistent ghost ghostMulDivDown(mathint, mathint, mathint) returns mathint;

persistent ghost ghostMulDivUp(mathint, mathint, mathint) returns mathint;

/// CONCRETE SUB-LEMMAS (each is a small standalone sub-goal over the real mulDiv) ///

// L1 == Rocq seized_value_drop_le_maxSeizedValue (:141) / MulDiv.spec mulDivInverseUpDown.
// Valuing (ceil) the assets that a floor-seize took never exceeds what was seized in value: up(down(a,b,d),d,b) <= a.
rule lemmaInverseUpDown(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(mulDivDown(a, b, d), d, b) <= a;
}

// L2 & L3 == Rocq floor_drop_div_le_ceil (:122) / MulDiv.spec mulDivAddDownUp.
// A floor drop over an added chunk is bounded by the ceil of that chunk: down(a1+a2,b,d) <= down(a1,b,d)+up(a2,b,d).
rule lemmaDropLeCeil(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1plusa2, b, d) <= mulDivDown(a1, b, d) + mulDivUp(a2, b, d);
}

// L4 == Rocq ceil_div_mono (:112) / MulDiv.spec mulDivMonotoneA (up leg): ceil is monotone in its numerator.
rule lemmaMonotoneUpNum(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    assert a1 <= a2 => mulDivUp(a1, b, d) <= mulDivUp(a2, b, d);
}

// Monotonicity of floor in its numerator (used to know newCollatValue <= curCollatValue, i.e. the drop is >= 0).
rule lemmaMonotoneDownNum(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    assert a1 <= a2 => mulDivDown(a1, b, d) <= mulDivDown(a2, b, d);
}

// L5.a == Rocq floor_mul_le (:75) / MulDiv.spec mulDivDownRoundsDown: down(a,b,d)*d <= a*b.
rule lemmaDownRoundsDown(uint256 a, uint256 b, uint256 d) {
    assert mulDivDown(a, b, d) * d <= a * b;
}

// L5.b == Rocq ceil_div_mul_ge (:87) / MulDiv.spec mulDivUpRoundsUp: up(a,b,d)*d >= a*b.
rule lemmaUpRoundsUp(uint256 a, uint256 b, uint256 d) {
    assert mulDivUp(a, b, d) * d >= a * b;
}

// L5.c == Rocq ceil_div_le_of_mul_ge (:100) / MulDiv.spec mulDivCeilLeOfMulGe:
// if the exact product is at most bound*d then the ceiling is at most bound.
rule lemmaCeilLeOfMulGe(uint256 a, uint256 b, uint256 d, uint256 bound) {
    assert d != 0 && a * b <= bound * d => mulDivUp(a, b, d) <= bound;
}

// mulDiv of non-negatives is non-negative (uint256 result). Needed to pin the sign of the ghost values below.
rule lemmaNonneg(uint256 a, uint256 b, uint256 d) {
    assert mulDivDown(a, b, d) >= 0;
    assert mulDivUp(a, b, d) >= 0;
}

/// COMPOSITION (the discharge of axiomMaxDebtDrop) ///

// The LLTV-weighted maxDebt contribution drops by at most ceil(maxRepaid * lif * lltv / WAD^2) when seized is the
// L692 seizedAssets = floor(floor(maxRepaid * lif / WAD) * OPS / price). See rocq/maxRepaidHealthy.v:162. Proven over
// UNINTERPRETED mulDiv (ghost*), assuming each nested fact in the exact instance the concrete sub-lemmas above prove,
// then closing with linear/NIA glue -- exactly the composition structure of the Rocq proof body (:180-246).
rule maxDebtContributionDropBound(uint256 collat, uint256 price, uint256 lltv, uint256 maxRepaid, uint256 lif) {
    require price > 0, "0 < price";
    require lltv <= WAD(), "enabled lltv <= WAD";
    require lif <= 2 * WAD(), "maxLif <= 2 * WAD (see Midnight.sol:810)";

    mathint W = WAD();
    mathint S = ORACLE_PRICE_SCALE();

    // Ghost-form quantities, mirroring the concrete definitions of the original monolithic rule.
    mathint maxSeizedValue = ghostMulDivDown(maxRepaid, lif, W);
    mathint seized = ghostMulDivDown(maxSeizedValue, S, price);
    require seized <= collat, "seized <= collateral (else liquidate reverts)";
    mathint collatMinusSeized = collat - seized;

    mathint curCollatValue = ghostMulDivDown(collat, price, S);
    mathint newCollatValue = ghostMulDivDown(collatMinusSeized, price, S);
    mathint collatValueDrop = curCollatValue - newCollatValue;

    mathint curContrib = ghostMulDivDown(curCollatValue, lltv, W);
    mathint newContrib = ghostMulDivDown(newCollatValue, lltv, W);

    mathint lifTimesLltv = lif * lltv;
    mathint wadSquared = W * W;
    mathint maxDebtDropBound = ghostMulDivUp(maxRepaid, lifTimesLltv, wadSquared);

    // Non-negativity of the ghost values (lemmaNonneg).
    require maxSeizedValue >= 0 && seized >= 0;
    require curCollatValue >= 0 && newCollatValue >= 0;
    require curContrib >= 0 && newContrib >= 0;
    require maxDebtDropBound >= 0;

    // L1 (lemmaInverseUpDown), instance a=maxSeizedValue, b=S, d=price:
    //   up(down(maxSeizedValue,S,price),price,S) == up(seized,price,S) <= maxSeizedValue.
    require ghostMulDivUp(seized, price, S) <= maxSeizedValue;

    // L2 (lemmaDropLeCeil), instance a1=collatMinusSeized, a2=seized, b=price, d=S (a1+a2 == collat):
    //   curCollatValue <= newCollatValue + up(seized,price,S).
    require curCollatValue <= newCollatValue + ghostMulDivUp(seized, price, S);

    // newCollatValue <= curCollatValue (lemmaMonotoneDownNum, collatMinusSeized <= collat): the drop is >= 0.
    require newCollatValue <= curCollatValue;

    // L3 (lemmaDropLeCeil), instance a1=newCollatValue, a2=collatValueDrop, b=lltv, d=W (a1+a2 == curCollatValue):
    //   curContrib <= newContrib + up(collatValueDrop,lltv,W).
    require curContrib <= newContrib + ghostMulDivUp(collatValueDrop, lltv, W);

    // L4 (lemmaMonotoneUpNum), instance a1=collatValueDrop, a2=maxSeizedValue, b=lltv, d=W.
    require collatValueDrop <= maxSeizedValue => ghostMulDivUp(collatValueDrop, lltv, W) <= ghostMulDivUp(maxSeizedValue, lltv, W);

    // L5.a (lemmaDownRoundsDown), instance a=maxRepaid, b=lif, d=W: maxSeizedValue*W <= maxRepaid*lif.
    require maxSeizedValue * W <= maxRepaid * lif;

    // L5.b (lemmaUpRoundsUp), instance a=maxRepaid, b=lifTimesLltv, d=wadSquared:
    //   maxDebtDropBound*wadSquared >= maxRepaid*lifTimesLltv.
    require maxDebtDropBound * wadSquared >= maxRepaid * lifTimesLltv;

    // L5.c (lemmaCeilLeOfMulGe), instance a=maxSeizedValue, b=lltv, d=W, bound=maxDebtDropBound:
    //   maxSeizedValue*lltv <= maxDebtDropBound*W  =>  up(maxSeizedValue,lltv,W) <= maxDebtDropBound.
    require maxSeizedValue * lltv <= maxDebtDropBound * W => ghostMulDivUp(maxSeizedValue, lltv, W) <= maxDebtDropBound;

    // --- linear / NIA glue (mirrors rocq/maxRepaidHealthy.v:185-246), no nested division here ---
    // (a) collatValueDrop <= maxSeizedValue: from L2 (drop <= up(seized,price,S)) and L1 (up(seized,..) <= maxSeizedValue).
    // (b) up(collatValueDrop,lltv,W) <= up(maxSeizedValue,lltv,W): L4 with (a).
    // (c) up(maxSeizedValue,lltv,W) <= maxDebtDropBound: from L5.a * lltv, L5.b, cancel W>0, then L5.c.
    // (d) curContrib - newContrib <= up(collatValueDrop,lltv,W) (L3), chained through (b),(c).

    assert curContrib - newContrib <= maxDebtDropBound;
}
