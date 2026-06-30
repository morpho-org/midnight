From Stdlib Require Import ZArith Lia Psatz.

Open Scope Z_scope.

Definition WAD : Z := 10 ^ 18.
Definition ORACLE_PRICE_SCALE : Z := 10 ^ 36.

Definition ceil_div (numerator denominator : Z) : Z :=
  (numerator + denominator - 1) / denominator.

Definition zeroFloorSub (x y : Z) : Z :=
  Z.max 0 (x - y).

(* -------------------------------------------------------------------------- *)
(* Main statement: a liquidation never creates realizable bad debt.           *)
(* (Proved below as liquidation_no_bad_debt, after the supporting lemmas.)     *)
(* -------------------------------------------------------------------------- *)

(**
Setup (mirrors liquidate in src/Midnight.sol):

- _collateral, liquidatedCollatPrice, _maxLif: the liquidated collateral.
- otherCollateralRepayableUnits: the repayable units of every *other*
  collateral of the position (>= 0). It does not change during the liquidation,
  since only the liquidated collateral is reduced. (The contract accumulates
  these amounts with an iterated zeroFloorSub; because every term is
  non-negative this equals one zeroFloorSub of the full sum, which is what badDebt
  below models.)
- badDebt is the realizable bad debt that the contract realizes up-front.
- repaidUnits is then subtracted from the debt, and seizedAssets from the
  collateral, linked by the contract's formula in one of the two input
  modes ("seizedAssets given" or "repaidUnits given"), with the applied
  incentive factor satisfying 0 < lif <= _maxLif.

Conclusion: the new realizable bad debt of the position is 0.
This is an integer-arithmetic proof; it uses no real-number approximation.
The hypothesis seizedAssets <= _collateral does not narrow generality:
otherwise the collateral subtraction underflows and the whole transaction
reverts.
*)
Definition liquidation_no_bad_debt_statement : Prop :=
  forall originalDebt otherCollateralRepayableUnits _collateral seizedAssets
    liquidatedCollatPrice _maxLif lif repaidUnits,
    let badDebt := zeroFloorSub originalDebt
      (otherCollateralRepayableUnits +
        ceil_div
          (ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
          _maxLif) in
    0 <= liquidatedCollatPrice -> 0 < _maxLif ->
    0 < lif -> lif <= _maxLif ->
    0 <= originalDebt -> 0 <= otherCollateralRepayableUnits ->
    0 <= _collateral -> 0 <= seizedAssets -> seizedAssets <= _collateral ->
    0 <= repaidUnits ->
    (* Covers the repaidUnits = 0 && seizedAssets = 0 case. *)
    ( repaidUnits =
        ceil_div
          (ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
          lif
      \/ (0 < liquidatedCollatPrice /\
          seizedAssets =
            repaidUnits * lif / WAD * ORACLE_PRICE_SCALE / liquidatedCollatPrice) ) ->
    let newCollateral := _collateral - seizedAssets in
    let newBadDebt := zeroFloorSub (originalDebt - badDebt - repaidUnits)
      (otherCollateralRepayableUnits +
        ceil_div
          (ceil_div
            (newCollateral * liquidatedCollatPrice)
            ORACLE_PRICE_SCALE * WAD)
          _maxLif) in
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

(* Seizing seizedAssets out of _collateral drops the repayable amount by at
   most the repayable amount of the seized chunk. *)
Lemma seize_repayableUp_drop_le :
  forall _collateral seizedAssets liquidatedCollatPrice _maxLif,
    0 <= liquidatedCollatPrice -> 0 < _maxLif ->
    0 <= seizedAssets -> seizedAssets <= _collateral ->
    ceil_div
        (ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
        _maxLif
      - ceil_div
          (ceil_div
            ((_collateral - seizedAssets) * liquidatedCollatPrice)
            ORACLE_PRICE_SCALE * WAD)
          _maxLif
      <= ceil_div
          (ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
          _maxLif.
Proof.
  intros _collateral seizedAssets liquidatedCollatPrice _maxLif
    Hprice HmaxLif Hseized Hsc.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  assert (HnewCollateralValue :
    0 <= ceil_div
      ((_collateral - seizedAssets) * liquidatedCollatPrice)
      ORACLE_PRICE_SCALE).
  { apply ceil_div_nonneg; [ exact Hscale | nia ]. }
  assert (HnewCollateralValueLe :
    ceil_div
        ((_collateral - seizedAssets) * liquidatedCollatPrice)
        ORACLE_PRICE_SCALE
      <= ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE).
  { apply ceil_div_mono; [ exact Hscale | nia ]. }
  assert (Hinner :
    ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE
      - ceil_div
          ((_collateral - seizedAssets) * liquidatedCollatPrice)
          ORACLE_PRICE_SCALE
      <= ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE).
  {
    pose proof (ceil_div_subadd
                  ((_collateral - seizedAssets) * liquidatedCollatPrice)
                  (seizedAssets * liquidatedCollatPrice)
                  ORACLE_PRICE_SCALE Hscale ltac:(nia) ltac:(nia)) as Hsub.
    replace
      ((_collateral - seizedAssets) * liquidatedCollatPrice +
        seizedAssets * liquidatedCollatPrice)
      with (_collateral * liquidatedCollatPrice) in Hsub by nia.
    lia.
  }
  assert (Hdrop :
    ceil_div
        (ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
        _maxLif
      - ceil_div
          (ceil_div
            ((_collateral - seizedAssets) * liquidatedCollatPrice)
            ORACLE_PRICE_SCALE * WAD)
          _maxLif
      <= ceil_div
          ((ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD) -
            (ceil_div
              ((_collateral - seizedAssets) * liquidatedCollatPrice)
              ORACLE_PRICE_SCALE * WAD))
          _maxLif).
  { apply ceil_div_drop; [ exact HmaxLif | nia | nia ]. }
  assert (Hmono :
    ceil_div
        ((ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD) -
          (ceil_div
            ((_collateral - seizedAssets) * liquidatedCollatPrice)
            ORACLE_PRICE_SCALE * WAD))
        _maxLif
      <= ceil_div
          (ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
          _maxLif).
  { apply ceil_div_mono; [ exact HmaxLif | nia ]. }
  lia.
Qed.

(* In the "repaidUnits given" branch, the contract computes
     seizedAssets = mulDivDown(mulDivDown(repaidUnits, lif, WAD),
       ORACLE_PRICE_SCALE, liquidatedCollatPrice).
   The repayable amount of that seized chunk is at most repaidUnits,
   because lif <= _maxLif. *)
Lemma repayableUp_seized_le_repaid :
  forall seizedAssets liquidatedCollatPrice _maxLif lif repaidUnits,
    0 < liquidatedCollatPrice -> 0 < _maxLif ->
    0 < lif -> lif <= _maxLif -> 0 <= repaidUnits ->
    seizedAssets =
      repaidUnits * lif / WAD * ORACLE_PRICE_SCALE / liquidatedCollatPrice ->
    ceil_div
        (ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
        _maxLif
      <= repaidUnits.
Proof.
  intros seizedAssets liquidatedCollatPrice _maxLif lif repaidUnits
    Hprice HmaxLif Hlif Hlifmax Hrepaid Hseized.
  assert (Hscale : 0 < ORACLE_PRICE_SCALE) by apply ORACLE_PRICE_SCALE_pos.
  assert (HWAD : 0 < WAD) by apply WAD_pos.
  assert (HrepaidValue : 0 <= repaidUnits * lif / WAD).
  { apply Z.div_pos; nia. }
  assert (Hseized0 : 0 <= seizedAssets).
  { rewrite Hseized. apply Z.div_pos; nia. }
  assert (HSq :
    ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE
      <= repaidUnits * lif / WAD).
  {
    apply ceil_div_le_of_mul_ge.
    - exact Hscale.
    - nia.
    - rewrite Hseized.
      pose proof
        (floor_mul_le
          (repaidUnits * lif / WAD * ORACLE_PRICE_SCALE)
          liquidatedCollatPrice Hprice ltac:(nia)) as Hf.
      nia.
  }
  assert (Hmono :
    ceil_div
        (ceil_div (seizedAssets * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
        _maxLif
      <= ceil_div (repaidUnits * lif / WAD * WAD) _maxLif).
  { apply ceil_div_mono; [ exact HmaxLif | nia ]. }
  assert (Hfinal :
    ceil_div (repaidUnits * lif / WAD * WAD) _maxLif <= repaidUnits).
  {
    apply ceil_div_le_of_mul_ge.
    - exact HmaxLif.
    - nia.
    - pose proof
        (floor_mul_le (repaidUnits * lif) WAD HWAD ltac:(nia)) as Hf2.
      nia.
  }
  lia.
Qed.

(* -------------------------------------------------------------------------- *)
(* Proof of the main statement                                                *)
(* -------------------------------------------------------------------------- *)

Theorem liquidation_no_bad_debt : liquidation_no_bad_debt_statement.
Proof.
  unfold liquidation_no_bad_debt_statement.
  intros originalDebt otherCollateralRepayableUnits _collateral seizedAssets
    liquidatedCollatPrice _maxLif lif repaidUnits.
  cbv zeta.
  unfold zeroFloorSub.
  intros Hprice HmaxLif Hlif Hlifmax Hdebt Hother Hcollateral Hseized Hsc Hrepaid Hbranch.
  assert (Hdelta :
    ceil_div
        (ceil_div (_collateral * liquidatedCollatPrice) ORACLE_PRICE_SCALE * WAD)
        _maxLif
      - ceil_div
          (ceil_div
            ((_collateral - seizedAssets) * liquidatedCollatPrice)
            ORACLE_PRICE_SCALE * WAD)
          _maxLif
      <= repaidUnits).
  {
    pose proof
      (seize_repayableUp_drop_le
        _collateral seizedAssets liquidatedCollatPrice _maxLif
        Hprice HmaxLif Hseized Hsc) as Hcore.
    destruct Hbranch as [Hb1 | Hb2].
    - assert (Hanti :
        ceil_div
            (ceil_div
              (seizedAssets * liquidatedCollatPrice)
              ORACLE_PRICE_SCALE * WAD)
            _maxLif
          <= ceil_div
              (ceil_div
                (seizedAssets * liquidatedCollatPrice)
                ORACLE_PRICE_SCALE * WAD)
              lif).
      {
        apply ceil_div_denom_antitone; [ exact Hlif | exact Hlifmax | ].
        apply Z.mul_nonneg_nonneg.
        - apply ceil_div_nonneg; [ apply ORACLE_PRICE_SCALE_pos | nia ].
        - apply Z.lt_le_incl, WAD_pos.
      }
      lia.
    - destruct Hb2 as [HpricePositive Hb2].
      pose proof
        (repayableUp_seized_le_repaid
          seizedAssets liquidatedCollatPrice _maxLif lif repaidUnits
          HpricePositive HmaxLif Hlif Hlifmax Hrepaid Hb2) as Hd2.
      lia.
  }
  lia.
Qed.
