From Stdlib Require Import ZArith Lia.

Open Scope Z_scope.

Definition WAD : Z := 10 ^ 18.

Definition ceil_div (numerator denominator : Z) : Z :=
  (numerator + denominator - 1) / denominator.

(**
If the ideal max debt is underestimated by maxDebtError, then
the resulting maxRepaid overestimation is bounded by maxDebtError / (1 - lif * lltv).
*)
Definition max_repaid_overestimation_statement : Prop :=
  forall debt idealMaxDebt maxDebtError lltv lif,
    let toMaxRepaid maxDebt :=
      ceil_div ((debt - maxDebt) * (WAD * WAD))
        (WAD * WAD - lif * lltv) in
    0 <= debt ->
    idealMaxDebt - maxDebtError < debt ->
    0 <= maxDebtError -> maxDebtError <= idealMaxDebt ->
    0 <= lltv -> lltv < WAD ->
    0 <= lif ->
    lif * lltv < WAD * WAD ->
    (* Borrower is only liquidatable because maxDebt is underestimated: bound maxRepaid. *)
    (debt <= idealMaxDebt /\
      toMaxRepaid (idealMaxDebt - maxDebtError)
        <= ceil_div (maxDebtError * (WAD * WAD)) (WAD * WAD - lif * lltv))
    \/
    (* Borrower is legitimately liquidatable: bound the maxRepaid error. *)
    (idealMaxDebt < debt /\
      toMaxRepaid (idealMaxDebt - maxDebtError) - toMaxRepaid idealMaxDebt
        <= ceil_div (maxDebtError * (WAD * WAD)) (WAD * WAD - lif * lltv)).

(**
If lif * lltv is at most 0.999, error is ampified by at most 1000.
*)
Definition max_repaid_overestimation_factor_1000_statement : Prop :=
  forall debt idealMaxDebt maxDebtError lltv lif,
    let toMaxRepaid maxDebt :=
      ceil_div ((debt - maxDebt) * (WAD * WAD))
        (WAD * WAD - lif * lltv) in
    0 <= debt ->
    idealMaxDebt - maxDebtError < debt ->
    0 <= maxDebtError -> maxDebtError <= idealMaxDebt ->
    0 <= lltv -> lltv < WAD ->
    0 <= lif ->
    lif * lltv <= (999 * WAD * WAD) / 1000 ->
    (* Borrower should not be liquidatable but is because maxDebt is underestimated: bound the whole maxRepaid. *)
    (debt <= idealMaxDebt /\
      toMaxRepaid (idealMaxDebt - maxDebtError) <= 1000 * maxDebtError)
    \/
    (* Borrower liquidatable: bound the excess of Solidity's maxRepaid over the ideal one. *)
    (idealMaxDebt < debt /\
      toMaxRepaid (idealMaxDebt - maxDebtError) - toMaxRepaid idealMaxDebt <= 1000 * maxDebtError).

Lemma ceil_div_mono :
  forall left right denominator,
    0 < denominator -> left <= right ->
    ceil_div left denominator <= ceil_div right denominator.
Proof.
  intros left right denominator Hden Hle.
  unfold ceil_div.
  apply Z.div_le_mono; lia.
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

Lemma ceil_div_add_le :
  forall left right denominator,
    0 < denominator -> 0 <= left -> 0 <= right ->
    ceil_div (left + right) denominator
      <= ceil_div left denominator + ceil_div right denominator.
Proof.
  intros left right denominator Hden Hleft Hright.
  set (leftCeil := ceil_div left denominator).
  set (rightCeil := ceil_div right denominator).
  assert (HleftCeil : left <= leftCeil * denominator).
  { subst leftCeil. apply ceil_div_mul_ge; lia. }
  assert (HrightCeil : right <= rightCeil * denominator).
  { subst rightCeil. apply ceil_div_mul_ge; lia. }
  subst leftCeil rightCeil.
  unfold ceil_div at 1.
  apply Z.lt_succ_r.
  apply Z.div_lt_upper_bound.
  - exact Hden.
  - nia.
Qed.

Theorem max_repaid_overestimation :
  max_repaid_overestimation_statement.
Proof.
  unfold max_repaid_overestimation_statement.
  intros debt idealMaxDebt maxDebtError lltv lif.
  set (toMaxRepaid := fun maxDebt =>
    ceil_div ((debt - maxDebt) * (WAD * WAD)) (WAD * WAD - lif * lltv)).
  intros Hdebt HsolidityLiquidatable HmaxDebtError HmaxDebtErrorLeIdeal Hlltv HlltvLtWad Hlif HprodStrict.
  assert (Hden : 0 < WAD * WAD - lif * lltv) by lia.
  destruct (Z_le_gt_dec debt idealMaxDebt) as [HnotLiquidatable | Hliquidatable].
  - left.
    split.
    + exact HnotLiquidatable.
    + subst toMaxRepaid.
      apply ceil_div_mono.
      * exact Hden.
      * assert (HWAD2 : 0 < WAD * WAD) by (unfold WAD; lia).
        nia.
  - right.
    split.
    + lia.
    + subst toMaxRepaid.
      replace ((debt - (idealMaxDebt - maxDebtError)) * (WAD * WAD))
        with ((debt - idealMaxDebt) * (WAD * WAD) + maxDebtError * (WAD * WAD)) by ring.
      pose proof (
        ceil_div_add_le
          ((debt - idealMaxDebt) * (WAD * WAD))
          (maxDebtError * (WAD * WAD))
          (WAD * WAD - lif * lltv)
      ) as Hadd.
      specialize (Hadd ltac:(lia) ltac:(assert (HWAD2 : 0 < WAD * WAD) by (unfold WAD; lia); nia)
        ltac:(assert (HWAD2 : 0 < WAD * WAD) by (unfold WAD; lia); nia)).
      lia.
Qed.

Theorem max_repaid_overestimation_factor_1000 :
  max_repaid_overestimation_factor_1000_statement.
Proof.
  unfold max_repaid_overestimation_factor_1000_statement.
  intros debt idealMaxDebt maxDebtError lltv lif.
  set (toMaxRepaid := fun maxDebt =>
    ceil_div ((debt - maxDebt) * (WAD * WAD)) (WAD * WAD - lif * lltv)).
  intros Hdebt HsolidityLiquidatable HmaxDebtError HmaxDebtErrorLeIdeal Hlltv HlltvLtWad Hlif HprodBound.
  assert (HprodStrict : lif * lltv < WAD * WAD).
  {
    assert ((999 * WAD * WAD) / 1000 < WAD * WAD).
    {
      unfold WAD.
      apply Z.div_lt_upper_bound; nia.
    }
    lia.
  }
  assert (HamplifiedBound :
    ceil_div (maxDebtError * (WAD * WAD)) (WAD * WAD - lif * lltv) <= 1000 * maxDebtError).
  {
    unfold ceil_div.
    apply Z.lt_succ_r.
    apply Z.div_lt_upper_bound.
    - unfold WAD in *; lia.
    - assert (Hfloor :
        1000 * ((999 * WAD * WAD) / 1000) <= 999 * WAD * WAD).
      { apply Z.mul_div_le. lia. }
      assert (HscaledProd : 1000 * (lif * lltv) <= 999 * WAD * WAD) by nia.
      assert (HdenLower : WAD * WAD <= 1000 * (WAD * WAD - lif * lltv)) by nia.
      nia.
  }
  assert (Hmain :
    (debt <= idealMaxDebt /\
      toMaxRepaid (idealMaxDebt - maxDebtError)
        <= ceil_div (maxDebtError * (WAD * WAD)) (WAD * WAD - lif * lltv))
    \/
    (idealMaxDebt < debt /\
      toMaxRepaid (idealMaxDebt - maxDebtError) - toMaxRepaid idealMaxDebt
        <= ceil_div (maxDebtError * (WAD * WAD)) (WAD * WAD - lif * lltv))).
  {
    subst toMaxRepaid.
    eapply max_repaid_overestimation; eauto.
  }
  destruct Hmain as [[HnotLiquidatable Hbound] | [Hliquidatable Hbound]].
  - left.
    split.
    + exact HnotLiquidatable.
    + change (toMaxRepaid (idealMaxDebt - maxDebtError) <= 1000 * maxDebtError).
      lia.
  - right.
    split.
    + exact Hliquidatable.
    + change (toMaxRepaid (idealMaxDebt - maxDebtError) - toMaxRepaid idealMaxDebt <= 1000 * maxDebtError).
      lia.
Qed.
