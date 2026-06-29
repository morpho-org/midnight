From Stdlib Require Import ZArith Lia Psatz.

Open Scope Z_scope.

Definition WAD : Z := 1000000000000000000.
Definition ORACLE_PRICE_SCALE : Z := 1000000000000000000000000000000000000.

Definition ceil_div (numerator denominator : Z) : Z :=
  (numerator + denominator - 1) / denominator.

(* The per-collateral term the contract subtracts from the debt to measure the
   realizable bad debt: the debt units repayable by the collateral, valued at
   the worst-case incentive [maxLif] and rounded up. Mirrors the contract's
     mulDivUp(mulDivUp(collat, price, ORACLE_PRICE_SCALE), WAD, maxLif). *)
Definition repayableUp (collat price maxLif : Z) : Z :=
  ceil_div (ceil_div (collat * price) ORACLE_PRICE_SCALE * WAD) maxLif.

(* -------------------------------------------------------------------------- *)
(* Main statement: a liquidation never creates realizable bad debt.           *)
(* (Proved below as [liquidation_no_bad_debt], after the supporting lemmas.)   *)
(* -------------------------------------------------------------------------- *)

(**
Setup (mirrors [liquidate] in src/Midnight.sol):

- [collat], [price], [maxLif]: the liquidated collateral.
- [otherRepayableUp]: the repayable amount of every *other* collateral of the
  position (>= 0). It does not change during the liquidation, since only the
  liquidated collateral is reduced.  (The contract accumulates the per
  collateral repayable amounts with an iterated [zeroFloorSub]; because every
  term is non-negative this equals one [max 0] of the full sum, which is what
  [badDebt] below models.)
- [repayableUp collat price maxLif] is the contract's per-collateral term, i.e.
  the debt units the collateral can repay at the worst-case incentive maxLif.
- [badDebt = max(0, debt - totalRepayableUp)] is the realizable bad debt that
  the contract realizes up-front; afterwards [debtAfterRealization] is the
  remaining debt.
- [repaid] (repaidUnits) is then subtracted from the debt, and [seized] from
  the collateral, linked by the contract's formula in one of the two input
  modes ("seizedAssets given" or "repaidUnits given"), with the applied
  incentive factor satisfying 0 < lif <= maxLif.

Conclusion: the new realizable bad debt of the position is 0.
This is an integer-arithmetic proof; it uses no real-number approximation.
The hypothesis [seized <= collat] does not narrow generality: otherwise the
collateral subtraction underflows and the whole transaction reverts.
*)
Definition liquidation_no_bad_debt_statement : Prop :=
  forall debt otherRepayableUp collat seized price maxLif lif repaid,
    let totalRepayableUp := otherRepayableUp + repayableUp collat price maxLif in
    let badDebt := Z.max 0 (debt - totalRepayableUp) in
    let debtAfterRealization := debt - badDebt in
    let newDebt := debtAfterRealization - repaid in
    let newTotalRepayableUp :=
      otherRepayableUp + repayableUp (collat - seized) price maxLif in
    let newBadDebt := Z.max 0 (newDebt - newTotalRepayableUp) in
    0 < price -> 0 < maxLif ->
    0 < lif -> lif <= maxLif ->
    0 <= debt -> 0 <= otherRepayableUp ->
    0 <= collat -> 0 <= seized -> seized <= collat ->
    0 <= repaid ->
    ( repaid = ceil_div (ceil_div (seized * price) ORACLE_PRICE_SCALE * WAD) lif
      \/ seized = repaid * lif / WAD * ORACLE_PRICE_SCALE / price ) ->
    newBadDebt = 0.

(* -------------------------------------------------------------------------- *)
(* Generic integer-division lemmas                                            *)
(* -------------------------------------------------------------------------- *)

Lemma WAD_pos : 0 < WAD.
Proof. unfold WAD; lia. Qed.

Lemma ORACLE_PRICE_SCALE_pos : 0 < ORACLE_PRICE_SCALE.
Proof. unfold ORACLE_PRICE_SCALE; lia. Qed.

Lemma ceil_div_nonneg :
  forall numerator denominator,
    0 < denominator -> 0 <= numerator -> 0 <= ceil_div numerator denominator.
Proof.
  intros numerator denominator Hden Hnum.
  unfold ceil_div. apply Z.div_pos; lia.
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

(* ceil is subadditive: ceil((a+b)/n) <= ceil(a/n) + ceil(b/n). *)
Lemma ceil_div_subadd :
  forall a b denominator,
    0 < denominator -> 0 <= a -> 0 <= b ->
    ceil_div (a + b) denominator <= ceil_div a denominator + ceil_div b denominator.
Proof.
  intros a b denominator Hden Ha Hb.
  apply ceil_div_le_of_mul_ge.
  - exact Hden.
  - lia.
  - pose proof (ceil_div_mul_ge a denominator Hden Ha) as HA.
    pose proof (ceil_div_mul_ge b denominator Hden Hb) as HB.
    nia.
Qed.

(* The drop of a ceil-div is bounded by the ceil-div of the drop. *)
Lemma ceil_div_drop :
  forall p q denominator,
    0 < denominator -> 0 <= q -> q <= p ->
    ceil_div p denominator - ceil_div q denominator <= ceil_div (p - q) denominator.
Proof.
  intros p q denominator Hden Hq Hqp.
  pose proof (ceil_div_subadd q (p - q) denominator Hden Hq ltac:(lia)) as Hsub.
  replace (q + (p - q)) with p in Hsub by lia.
  lia.
Qed.

(* ceil-div is antitone in its (positive) denominator. *)
Lemma ceil_div_denom_antitone :
  forall numerator d1 d2,
    0 < d1 -> d1 <= d2 -> 0 <= numerator ->
    ceil_div numerator d2 <= ceil_div numerator d1.
Proof.
  intros numerator d1 d2 Hd1 Hd12 Hnum.
  apply ceil_div_le_of_mul_ge.
  - lia.
  - exact Hnum.
  - pose proof (ceil_div_mul_ge numerator d1 Hd1 Hnum) as H.
    pose proof (ceil_div_nonneg numerator d1 Hd1 Hnum) as Hpos.
    nia.
Qed.

(* -------------------------------------------------------------------------- *)
(* Midnight-specific lemmas                                                    *)
(* -------------------------------------------------------------------------- *)

(* Seizing [seized] out of [collat] drops the repayable amount by at most the
   repayable amount of the seized chunk. *)
Lemma seize_repayableUp_drop_le :
  forall collat seized price maxLif,
    0 < price -> 0 < maxLif ->
    0 <= seized -> seized <= collat ->
    repayableUp collat price maxLif - repayableUp (collat - seized) price maxLif
      <= repayableUp seized price maxLif.
Proof.
  intros collat seized price maxLif Hprice HmaxLif Hseized Hsc.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  unfold repayableUp.
  set (A := ceil_div (collat * price) ORACLE_PRICE_SCALE).
  set (B := ceil_div ((collat - seized) * price) ORACLE_PRICE_SCALE).
  set (S := ceil_div (seized * price) ORACLE_PRICE_SCALE).
  assert (HB0 : 0 <= B). { apply ceil_div_nonneg; [ exact Hscale | nia ]. }
  assert (HBA : B <= A). { apply ceil_div_mono; [ exact Hscale | nia ]. }
  (* Inner subadditivity: A - B <= S. *)
  assert (Hinner : A - B <= S).
  {
    unfold A, B, S.
    pose proof (ceil_div_subadd ((collat - seized) * price) (seized * price)
                  ORACLE_PRICE_SCALE Hscale ltac:(nia) ltac:(nia)) as Hsub.
    replace ((collat - seized) * price + seized * price) with (collat * price) in Hsub by nia.
    lia.
  }
  (* Outer drop, then monotonicity in the numerator. *)
  assert (Hdrop : ceil_div (A * WAD) maxLif - ceil_div (B * WAD) maxLif
                  <= ceil_div (A * WAD - B * WAD) maxLif).
  { apply ceil_div_drop; [ exact HmaxLif | nia | nia ]. }
  assert (Hmono : ceil_div (A * WAD - B * WAD) maxLif <= ceil_div (S * WAD) maxLif).
  { apply ceil_div_mono; [ exact HmaxLif | nia ]. }
  lia.
Qed.

(* In the "repaidUnits given" branch, the contract computes
     seized = mulDivDown(mulDivDown(repaid, lif, WAD), ORACLE_PRICE_SCALE, price).
   The repayable amount of that seized chunk is at most repaid,
   because lif <= maxLif. *)
Lemma repayableUp_seized_le_repaid :
  forall seized price maxLif lif repaid,
    0 < price -> 0 < maxLif -> 0 < lif -> lif <= maxLif -> 0 <= repaid ->
    seized = repaid * lif / WAD * ORACLE_PRICE_SCALE / price ->
    repayableUp seized price maxLif <= repaid.
Proof.
  intros seized price maxLif lif repaid Hprice HmaxLif Hlif Hlifmax Hrepaid Hseized.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  unfold repayableUp.
  set (q := repaid * lif / WAD).
  assert (Hseized_eq : seized = q * ORACLE_PRICE_SCALE / price).
  { rewrite Hseized. unfold q. reflexivity. }
  assert (Hq0 : 0 <= q). { unfold q. apply Z.div_pos; nia. }
  assert (Hseized0 : 0 <= seized).
  { rewrite Hseized_eq. apply Z.div_pos; nia. }
  (* Inner: ceil(seized*price / OPS) <= q. *)
  assert (HSq : ceil_div (seized * price) ORACLE_PRICE_SCALE <= q).
  {
    apply ceil_div_le_of_mul_ge.
    - exact Hscale.
    - nia.
    - rewrite Hseized_eq.
      pose proof (floor_mul_le (q * ORACLE_PRICE_SCALE) price Hprice ltac:(nia)) as Hf.
      nia.
  }
  (* Push through the outer ceil-div and bound by repaid. *)
  assert (Hmono : ceil_div (ceil_div (seized * price) ORACLE_PRICE_SCALE * WAD) maxLif
                  <= ceil_div (q * WAD) maxLif).
  { apply ceil_div_mono; [ exact HmaxLif | nia ]. }
  assert (Hfinal : ceil_div (q * WAD) maxLif <= repaid).
  {
    apply ceil_div_le_of_mul_ge.
    - exact HmaxLif.
    - nia.
    - pose proof (floor_mul_le (repaid * lif) WAD HWAD ltac:(nia)) as Hf2.
      unfold q. nia.
  }
  lia.
Qed.

(* -------------------------------------------------------------------------- *)
(* Proof of the main statement                                                *)
(* -------------------------------------------------------------------------- *)

Theorem liquidation_no_bad_debt : liquidation_no_bad_debt_statement.
Proof.
  unfold liquidation_no_bad_debt_statement.
  intros debt otherRepayableUp collat seized price maxLif lif repaid.
  cbv zeta.
  intros Hprice HmaxLif Hlif Hlifmax Hdebt Hother Hcollat Hseized Hsc Hrepaid Hbranch.
  (* Core: the repayable-amount drop on the liquidated collateral <= repaid. *)
  assert (Hdelta :
    repayableUp collat price maxLif - repayableUp (collat - seized) price maxLif
      <= repaid).
  {
    pose proof (seize_repayableUp_drop_le collat seized price maxLif
                  Hprice HmaxLif Hseized Hsc) as Hcore.
    destruct Hbranch as [Hb1 | Hb2].
    - (* "seizedAssets given": repaid is the same nested mulDivUp as the bad-debt
         term of [seized], but at the applied [lif] (<= maxLif). Since ceil-div is
         antitone in the incentive, that repaid is >= the term valued at maxLif. *)
      assert (Hanti : repayableUp seized price maxLif
                      <= ceil_div (ceil_div (seized * price) ORACLE_PRICE_SCALE * WAD) lif).
      {
        unfold repayableUp.
        apply ceil_div_denom_antitone; [ exact Hlif | exact Hlifmax | ].
        apply Z.mul_nonneg_nonneg.
        - apply ceil_div_nonneg; [ apply ORACLE_PRICE_SCALE_pos | nia ].
        - apply Z.lt_le_incl, WAD_pos.
      }
      lia.
    - (* "repaidUnits given". *)
      pose proof (repayableUp_seized_le_repaid seized price maxLif lif repaid
                    Hprice HmaxLif Hlif Hlifmax Hrepaid Hb2) as Hd2.
      lia.
  }
  (* Conclude: newDebt - newTotalRepayableUp <= 0, hence the max with 0 is 0. *)
  lia.
Qed.
