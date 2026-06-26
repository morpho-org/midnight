From Stdlib Require Import ZArith Lia Psatz.

Open Scope Z_scope.

Definition WAD : Z := 1000000000000000000.
Definition ORACLE_PRICE_SCALE : Z := 1000000000000000000000000000000000000.

Definition ceil_div (numerator denominator : Z) : Z :=
  (numerator + denominator - 1) / denominator.

(**
If:
- maxRepaid is computed as:
  ceil((debt - maxDebt) * WAD^2 / (WAD^2 - lif * lltv))
- repaid is the amount actually repaid: min(maxRepaid, debt)
- seizedAssets is computed as:
  floor(floor(repaid * lif / WAD) * ORACLE_PRICE_SCALE / price)
- maxDebt is computed from the current collateral as:
  otherCollatContribution + floor(floor(collat * price / ORACLE_PRICE_SCALE) * lltv / WAD)

then after liquidating repaid, the borrower is healthy:
  newDebt <= newMaxDebt

This proof is entirely over integer arithmetic.
It does not use real-number approximations.
The assumptions that the collateral seized does not exceed the current collateral does not narrow the generality of the proof: in that case the transaction would revert independently of the RCF mechanism, so that mechanism does not restrict the possibility to go back to health.
*)

Definition max_repaid_liquidation_leaves_healthy_statement : Prop :=
  forall debt otherCollatContribution collat price lltv lif,
    let maxDebt :=
      otherCollatContribution
      + (collat * price / ORACLE_PRICE_SCALE) * lltv / WAD in
    let maxRepaid :=
      ceil_div ((debt - maxDebt) * (WAD * WAD))
        (WAD * WAD - lif * lltv) in
    let repaid := Z.min maxRepaid debt in
    let seizedAssets :=
      (repaid * lif / WAD * ORACLE_PRICE_SCALE) / price in
    let newDebt := debt - repaid in
    let newMaxDebt :=
      otherCollatContribution
      + ((collat - seizedAssets) * price / ORACLE_PRICE_SCALE) * lltv / WAD in
    0 < price ->
    0 <= debt -> 0 <= otherCollatContribution ->
    0 <= collat ->
    0 <= lltv -> 0 <= lif ->
    lif * lltv < WAD * WAD ->
    maxDebt <= debt ->
    seizedAssets <= collat ->
    0 <= newDebt /\ newDebt <= newMaxDebt.

(* -------------------------------------------------------------------------- *)
(* Generic integer-division lemmas                                             *)
(* -------------------------------------------------------------------------- *)

Lemma WAD_pos : 0 < WAD.
Proof. unfold WAD; lia. Qed.

Lemma ORACLE_PRICE_SCALE_pos : 0 < ORACLE_PRICE_SCALE.
Proof. unfold ORACLE_PRICE_SCALE; lia. Qed.

Lemma div_upper_strict :
  forall numerator denominator,
    0 < denominator -> 0 <= numerator ->
    numerator < denominator * (numerator / denominator + 1).
Proof.
  intros numerator denominator Hden Hnum.
  pose proof (Z.div_mod numerator denominator) as Hdivmod.
  specialize (Hdivmod ltac:(lia)).
  pose proof (Z.mod_pos_bound numerator denominator Hden) as Hmod.
  nia.
Qed.

Lemma floor_mul_le :
  forall numerator denominator,
    0 < denominator -> 0 <= numerator ->
    (numerator / denominator) * denominator <= numerator.
Proof.
  intros numerator denominator Hden Hnum.
  pose proof (Z.div_mod numerator denominator) as Hdivmod.
  specialize (Hdivmod ltac:(lia)).
  pose proof (Z.mod_pos_bound numerator denominator Hden) as Hmod.
  nia.
Qed.

Lemma ceil_div_mul_ge :
  forall numerator denominator,
    0 < denominator -> 0 <= numerator ->
    numerator <= ceil_div numerator denominator * denominator.
Proof.
  intros numerator denominator Hden Hnum.
  unfold ceil_div.
  pose proof (Z.div_mod (numerator + denominator - 1) denominator) as Hdivmod.
  specialize (Hdivmod ltac:(lia)).
  pose proof (Z.mod_pos_bound (numerator + denominator - 1) denominator Hden) as Hmod.
  nia.
Qed.

Lemma ceil_div_le_of_mul_ge :
  forall numerator denominator bound,
    0 < denominator -> 0 <= numerator -> numerator <= bound * denominator ->
    ceil_div numerator denominator <= bound.
Proof.
  intros numerator denominator bound Hden Hnum Hbound.
  unfold ceil_div.
  assert ((numerator + denominator - 1) / denominator < bound + 1) as Hlt.
  { apply Z.div_lt_upper_bound; nia. }
  lia.
Qed.

Lemma ceil_div_mono :
  forall left right denominator,
    0 < denominator -> left <= right ->
    ceil_div left denominator <= ceil_div right denominator.
Proof.
  intros left right denominator Hden Hle.
  unfold ceil_div.
  apply Z.div_le_mono; lia.
Qed.

Lemma floor_drop_div_le_ceil :
  forall base drop denominator,
    0 < denominator -> 0 <= base -> 0 <= drop ->
    (base + drop) / denominator - base / denominator <= ceil_div drop denominator.
Proof.
  intros base drop denominator Hden Hbase Hdrop.
  assert (Hbase_lt : base < denominator * (base / denominator + 1)).
  { apply div_upper_strict; lia. }
  assert (Hdrop_le : drop <= ceil_div drop denominator * denominator).
  { apply ceil_div_mul_ge; lia. }
  assert ((base + drop) / denominator < base / denominator + ceil_div drop denominator + 1) as Hlt.
  { apply Z.div_lt_upper_bound; nia. }
  lia.
Qed.

(* -------------------------------------------------------------------------- *)
(* Midnight-specific rounding lemmas                                           *)
(* -------------------------------------------------------------------------- *)

Lemma seized_value_drop_le_maxSeizedValue :
  forall maxRepaid lif price seizedAssets,
    0 < price ->
    0 <= maxRepaid -> 0 <= lif ->
    seizedAssets = (maxRepaid * lif / WAD * ORACLE_PRICE_SCALE) / price ->
    ceil_div (seizedAssets * price) ORACLE_PRICE_SCALE <= maxRepaid * lif / WAD.
Proof.
  intros maxRepaid lif price seizedAssets Hprice HmaxRepaid Hlif Hseized.
  subst seizedAssets.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (HmaxSeizedValue_nonneg : 0 <= maxRepaid * lif / WAD).
  { apply Z.div_pos; nia. }
  apply ceil_div_le_of_mul_ge.
  - exact Hscale.
  - apply Z.mul_nonneg_nonneg; [apply Z.div_pos |]; nia.
  - pose proof (floor_mul_le (maxRepaid * lif / WAD * ORACLE_PRICE_SCALE) price Hprice) as Hfloor.
    specialize (Hfloor ltac:(nia)).
    nia.
Qed.

Lemma max_debt_contribution_drop_bound :
  forall collat seizedAssets price lltv maxRepaid lif,
    0 < price ->
    0 <= collat -> 0 <= seizedAssets -> seizedAssets <= collat ->
    0 <= lltv -> 0 <= maxRepaid -> 0 <= lif ->
    seizedAssets = (maxRepaid * lif / WAD * ORACLE_PRICE_SCALE) / price ->
    let currentCollatValue := collat * price / ORACLE_PRICE_SCALE in
    let newCollatValue := (collat - seizedAssets) * price / ORACLE_PRICE_SCALE in
    currentCollatValue * lltv / WAD - newCollatValue * lltv / WAD
      <= ceil_div (maxRepaid * lif * lltv) (WAD * WAD).
Proof.
  intros collat seizedAssets price lltv maxRepaid lif
    Hprice Hcollat HseizedNonneg HseizedLe Hlltv HmaxRepaid Hlif HseizedEq
    currentCollatValue newCollatValue.
  subst currentCollatValue newCollatValue.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.

  set (collatValueDrop :=
    collat * price / ORACLE_PRICE_SCALE - (collat - seizedAssets) * price / ORACLE_PRICE_SCALE).
  set (maxSeizedValue := maxRepaid * lif / WAD).
  set (maxDebtDropBound := ceil_div (maxRepaid * lif * lltv) (WAD * WAD)).

  assert (HcollatValueDrop_le : collatValueDrop <= maxSeizedValue).
  {
    unfold collatValueDrop, maxSeizedValue.
    replace (collat * price)
      with ((collat - seizedAssets) * price + seizedAssets * price) by nia.
    eapply Z.le_trans.
    - apply floor_drop_div_le_ceil; nia.
    - eapply seized_value_drop_le_maxSeizedValue; eauto; nia.
  }

  assert (Hold_ge_new_value :
    (collat - seizedAssets) * price / ORACLE_PRICE_SCALE <= collat * price / ORACLE_PRICE_SCALE).
  {
    apply Z.div_le_mono; nia.
  }

  assert (HmaxDebtDrop_by_valueDrop :
    collat * price / ORACLE_PRICE_SCALE * lltv / WAD
      - (collat - seizedAssets) * price / ORACLE_PRICE_SCALE * lltv / WAD
      <= ceil_div (collatValueDrop * lltv) WAD).
  {
    unfold collatValueDrop.
    replace (collat * price / ORACLE_PRICE_SCALE * lltv)
      with (((collat - seizedAssets) * price / ORACLE_PRICE_SCALE) * lltv
            + (collat * price / ORACLE_PRICE_SCALE - (collat - seizedAssets) * price / ORACLE_PRICE_SCALE) * lltv) by nia.
    eapply floor_drop_div_le_ceil.
    - exact HWAD.
    - apply Z.mul_nonneg_nonneg; try nia.
      apply Z.div_pos; nia.
    - apply Z.mul_nonneg_nonneg; nia.
  }

  assert (Hceil_valueDrop_le_maxSeizedValue :
    ceil_div (collatValueDrop * lltv) WAD <= ceil_div (maxSeizedValue * lltv) WAD).
  {
    apply ceil_div_mono; nia.
  }

  assert (HmaxSeizedValue_floor : maxSeizedValue * WAD <= maxRepaid * lif).
  {
    unfold maxSeizedValue.
    apply floor_mul_le; nia.
  }

  assert (HmaxDebtDropBound_mul : maxRepaid * lif * lltv <= maxDebtDropBound * (WAD * WAD)).
  {
    unfold maxDebtDropBound.
    apply ceil_div_mul_ge; nia.
  }

  assert (HmaxSeizedValue_to_maxDebtDropBound : maxSeizedValue * lltv <= maxDebtDropBound * WAD).
  {
    nia.
  }

  assert (Hceil_maxSeizedValue_le_maxDebtDropBound :
    ceil_div (maxSeizedValue * lltv) WAD <= maxDebtDropBound).
  {
    apply ceil_div_le_of_mul_ge; nia.
  }

  lia.
Qed.

(* -------------------------------------------------------------------------- *)
(* Final theorem                                                               *)
(* -------------------------------------------------------------------------- *)

Theorem max_repaid_liquidation_leaves_healthy :
  max_repaid_liquidation_leaves_healthy_statement.
Proof.
  unfold max_repaid_liquidation_leaves_healthy_statement.
  intros debt otherCollatContribution collat price lltv lif.
  set (maxDebt := otherCollatContribution + collat * price / ORACLE_PRICE_SCALE * lltv / WAD).
  set (maxRepaid := ceil_div ((debt - maxDebt) * (WAD * WAD)) (WAD * WAD - lif * lltv)).
  set (repaid := Z.min maxRepaid debt).
  set (seizedAssets := repaid * lif / WAD * ORACLE_PRICE_SCALE / price).
  set (newDebt := debt - repaid).
  set (newMaxDebt := otherCollatContribution + (collat - seizedAssets) * price / ORACLE_PRICE_SCALE * lltv / WAD).
  intros Hprice Hdebt Hother Hcollat Hlltv Hlif Hden HmaxDebtLeDebt HseizedLeCollat.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (Hden_pos : 0 < WAD * WAD - lif * lltv) by nia.
  assert (HmaxDebt_nonneg : 0 <= maxDebt).
  {
    subst maxDebt.
    assert (HcollatValue_nonneg : 0 <= collat * price / ORACLE_PRICE_SCALE).
    { apply Z.div_pos; nia. }
    assert (HcollatContribution_nonneg : 0 <= collat * price / ORACLE_PRICE_SCALE * lltv / WAD).
    { apply Z.div_pos; nia. }
    nia.
  }
  assert (HmaxRepaid_nonneg : 0 <= maxRepaid).
  {
    subst maxRepaid.
    unfold ceil_div.
    apply Z.div_pos; nia.
  }
  assert (Hrepaid_nonneg : 0 <= repaid).
  {
    subst repaid.
    apply Z.min_glb; assumption.
  }
  assert (Hrepaid_le_debt : repaid <= debt).
  {
    subst repaid.
    apply Z.le_min_r.
  }
  split.
  - subst newDebt; lia.
  - destruct (Z.leb_spec0 debt maxRepaid) as [Hdebt_le_maxRepaid | HmaxRepaid_lt_debt].
    + assert (Hrepaid_eq : repaid = debt).
      { subst repaid. apply Z.min_r. lia. }
      subst newDebt newMaxDebt.
      rewrite Hrepaid_eq.
      assert (Hseized_nonneg : 0 <= seizedAssets).
      {
        subst seizedAssets.
        rewrite Hrepaid_eq.
        apply Z.div_pos.
        - apply Z.mul_nonneg_nonneg.
          + apply Z.div_pos; nia.
          + lia.
        - lia.
      }
      assert (HnewCollatValue_nonneg : 0 <= (collat - seizedAssets) * price / ORACLE_PRICE_SCALE).
      { apply Z.div_pos; nia. }
      assert (HnewContribution_nonneg :
        0 <= (collat - seizedAssets) * price / ORACLE_PRICE_SCALE * lltv / WAD).
      { apply Z.div_pos; nia. }
      nia.
    + assert (Hrepaid_eq : repaid = maxRepaid).
      { subst repaid. apply Z.min_l. lia. }
      set (gap := debt - maxDebt).
      set (maxDebtDropBound := ceil_div (maxRepaid * lif * lltv) (WAD * WAD)).
      assert (Hgap_nonneg : 0 <= gap) by (unfold gap; lia).
      assert (HmaxRepaid_def_le :
        gap * (WAD * WAD) <= maxRepaid * (WAD * WAD - lif * lltv)).
      {
        subst maxRepaid.
        unfold gap.
        apply ceil_div_mul_ge; nia.
      }
      assert (Hextra_mul :
        (maxRepaid - gap) * (WAD * WAD) >= maxRepaid * lif * lltv).
      { nia. }
      assert (HmaxDebtDropBound_le_extra : maxDebtDropBound <= maxRepaid - gap).
      {
        unfold maxDebtDropBound.
        apply ceil_div_le_of_mul_ge; nia.
      }
      assert (Hseized_nonneg : 0 <= seizedAssets).
      {
        subst seizedAssets.
        rewrite Hrepaid_eq.
        apply Z.div_pos.
        - apply Z.mul_nonneg_nonneg.
          + apply Z.div_pos; nia.
          + lia.
        - lia.
      }
      assert (HseizedEq : seizedAssets = maxRepaid * lif / WAD * ORACLE_PRICE_SCALE / price).
      {
        subst seizedAssets.
        rewrite Hrepaid_eq.
        reflexivity.
      }
      assert (HmaxDebtDrop_le_bound : maxDebt - newMaxDebt <= maxDebtDropBound).
      {
        subst maxDebt newMaxDebt.
        replace (otherCollatContribution + collat * price / ORACLE_PRICE_SCALE * lltv / WAD -
          (otherCollatContribution + (collat - seizedAssets) * price / ORACLE_PRICE_SCALE * lltv / WAD))
          with (collat * price / ORACLE_PRICE_SCALE * lltv / WAD -
            (collat - seizedAssets) * price / ORACLE_PRICE_SCALE * lltv / WAD) by lia.
        unfold maxDebtDropBound.
        eapply max_debt_contribution_drop_bound; eauto; nia.
      }
      subst newDebt.
      rewrite Hrepaid_eq.
      unfold gap in *.
      lia.
Qed.
