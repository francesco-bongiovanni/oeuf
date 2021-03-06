Require Import oeuf.Common.

Require Import oeuf.Utopia.
Require Import oeuf.Metadata.
Require Import Program.

Require Import oeuf.HList.
Require Import oeuf.CompilationUnit.
Require Import oeuf.Semantics.
Require Import oeuf.HighestValues.

Require oeuf.Untyped1.
Require oeuf.Untyped2.
Require oeuf.Untyped3.

Module A := Untyped2.
Module B := Untyped3.
Module S := Untyped1.


Definition compile_genv := @id (list S.expr).

Definition compile_cu := @id (list S.expr * list metadata)%type.


Ltac i_ctor := intros; constructor; eauto.
Ltac i_lem H := intros; eapply H; eauto.

Theorem I_sim : forall (AE BE : list S.expr) s s',
    compile_genv AE = BE ->
    A.sstep AE s s' ->
    B.sstep BE s s'.

destruct s as [e l k | v];
intros0 Henv Astep; inv Astep.
all: try solve [i_ctor].

- unfold S.run_elim in *. repeat (break_match; try discriminate). inject_some.
  i_lem B.SEliminate.
Qed.



Lemma compile_cu_eq : forall A Ameta B Bmeta,
    compile_cu (A, Ameta) = (B, Bmeta) ->
    A = B.
simpl. inversion 1. auto.
Qed.

Lemma compile_cu_metas : forall A Ameta B Bmeta,
    compile_cu (A, Ameta) = (B, Bmeta) ->
    Ameta = Bmeta.
simpl. inversion 1. auto.
Qed.

Section Preservation.

    Variable aprog : A.prog_type.
    Variable bprog : B.prog_type.

    Hypothesis Hcomp : compile_cu aprog = bprog.

    Theorem fsim : Semantics.forward_simulation (A.semantics aprog) (B.semantics bprog).
    destruct aprog as [A Ameta], bprog as [B Bmeta].
    fwd eapply compile_cu_eq; eauto.
    fwd eapply compile_cu_metas; eauto.

    eapply Semantics.forward_simulation_step with
        (match_states := @eq S.state)
        (match_values := @eq value).

    - simpl. intros0 Bcall Hf Ha. invc Bcall.
      simpl in *.
      eexists. split; repeat i_ctor.

    - simpl. intros0 II Afinal. invc Afinal.
      eexists. split. i_ctor. i_ctor.

    - intros0 Astep. intros0 II.
      fwd eapply I_sim; eauto.
      subst s1. eexists. eauto.

    Defined.

    Lemma match_val_eq :
      Semantics.fsim_match_val _ _ fsim = eq.
    Proof.
      unfold fsim. simpl.
      unfold Semantics.fsim_match_val.
      break_match. repeat (break_match_hyp; try congruence).
      try unfold forward_simulation_step in *.
      try unfold forward_simulation_plus in *.
      try unfold forward_simulation_star in *.
      try unfold forward_simulation_star_wf in *.
      inv Heqf. reflexivity.
    Qed.
    

End Preservation.

