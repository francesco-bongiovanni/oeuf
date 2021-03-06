Require Import oeuf.Common oeuf.Monads oeuf.ListLemmas.
Require Import oeuf.Metadata.
Require oeuf.Tagged oeuf.TaggedNumbered.
Require String.
Require Import oeuf.HigherValue.

Module A := Tagged.
Module B := TaggedNumbered.

Delimit Scope string_scope with string.
Bind Scope string_scope with String.string.

Definition compiler_monad A := state (list (list (B.expr * B.rec_info))) A.


Section compile.
Open Scope state_monad.

Definition get_next : compiler_monad nat :=
    fun s => (length s, s).
Definition emit x : compiler_monad unit := fun s => (tt, s ++ [x]).

Definition compile : A.expr -> compiler_monad B.expr :=
    let fix go e :=
        let fix go_list es : compiler_monad (list B.expr) :=
            match es with
            | [] => ret_state []
            | e :: es => @cons B.expr <$> go e <*> go_list es
            end in
        let fix go_pair p : compiler_monad (B.expr * B.rec_info) :=
            let '(e, r) := p in
            go e >>= fun e' => ret_state (e', r) in
        let fix go_list_pair ps : compiler_monad (list (B.expr * B.rec_info)) :=
            match ps with
            | [] => ret_state []
            | p :: ps => cons <$> go_pair p <*> go_list_pair ps
            end in
        match e with
        | A.Arg => ret_state B.Arg
        | A.UpVar n => ret_state (B.UpVar n)
        | A.Call f a => B.Call <$> go f <*> go a
        | A.Constr tag args => B.Constr tag <$> go_list args
        | A.Elim cases target =>
                go_list_pair cases >>= fun cases' =>
                go target >>= fun target' =>
                get_next >>= fun n' =>
                emit cases' >>= fun _ =>
                ret_state (B.ElimN n' cases' target')
        | A.Close fname free => B.Close fname <$> go_list free
        end in go.

Definition compile_list :=
    let go := compile in
    let fix go_list es : compiler_monad (list B.expr) :=
        match es with
        | [] => ret_state []
        | e :: es => @cons B.expr <$> go e <*> go_list es
        end in go_list.

Definition compile_pair :=
    let go := compile in
    let fix go_pair p : compiler_monad (B.expr * B.rec_info) :=
        let '(e, r) := p in
        go e >>= fun e' => ret_state (e', r) in go_pair.

Definition compile_list_pair :=
    let go_pair := compile_pair in
    let fix go_list_pair ps : compiler_monad (list (B.expr * B.rec_info)) :=
        match ps with
        | [] => ret_state []
        | p :: ps => cons <$> go_pair p <*> go_list_pair ps
        end in go_list_pair.


Definition next_idx : state (nat * list String.string) nat :=
    fun s =>
    let '(idx, names) := s in
    (idx, (S idx, names)).

Definition record_name name : state (nat * list String.string) unit :=
    fun s =>
    let '(idx, names) := s in
    (tt, (idx, names ++ [name])).

Definition gen_elim_names : String.string -> A.expr -> state (nat * list String.string) unit :=
    let fix go name e :=
        let fix go_list name es :=
            match es with
            | [] => ret_state tt
            | e :: es => go name e >> go_list name es
            end in
        let fix go_pair name p :=
            let '(e, r) := p in go name e in
        let fix go_list_pair name ps :=
            match ps with
            | [] => ret_state tt
            | p :: ps => go_pair name p >> go_list_pair name ps
            end in
        match e with
        | A.Arg => ret_state tt
        | A.UpVar n => ret_state tt
        | A.Call f a => go name f >> go name a
        | A.Constr tag args => go_list name args
        | A.Elim cases target =>
                next_idx >>= fun idx =>
                let name' := String.append (String.append name "_elim") (nat_to_string idx) in
                go_list_pair name' cases >>
                go name' target >>
                record_name name'
        | A.Close fname free => go_list name free
        end in go.

Fixpoint gen_elim_names_list (exprs : list A.expr) (metas : list metadata) :
        state (nat * list String.string) unit :=
    match exprs, metas with
    | [], _ => ret_state tt
    | e :: es, [] =>
            gen_elim_names "anon" e >>= fun _ =>
            gen_elim_names_list es []
    | e :: es, m :: ms =>
            gen_elim_names (m_name m) e >>= fun _ =>
            gen_elim_names_list es ms
    end.


Definition compile_cu (cu : list A.expr * list metadata) :
        list B.expr * list metadata *
        list (list (B.expr * B.rec_info)) * list String.string :=
    let '(exprs, metas) := cu in
    let '(exprs', elims) := compile_list exprs [] in
    let '(tt, (_, elim_names)) := gen_elim_names_list exprs metas (0, []) in
    (exprs', metas, elims, elim_names).

End compile.

Ltac refold_compile :=
    fold compile_list in *;
    fold compile_pair in *;
    fold compile_list_pair in *.


Inductive I_expr : A.expr -> B.expr -> Prop :=
| IArg : I_expr A.Arg B.Arg
| IUpVar : forall n,
        I_expr (A.UpVar n) (B.UpVar n)
| ICall : forall af aa bf ba,
        I_expr af bf ->
        I_expr aa ba ->
        I_expr (A.Call af aa) (B.Call bf ba)
| IConstr : forall tag aargs bargs,
        Forall2 I_expr aargs bargs ->
        I_expr (A.Constr tag aargs) (B.Constr tag bargs)
| IElim : forall acases atarget num bcases btarget,
        Forall2 (fun ap bp => I_expr (fst ap) (fst bp) /\ snd ap = snd bp)
            acases bcases ->
        I_expr atarget btarget ->
        I_expr (A.Elim acases atarget)
               (B.ElimN num bcases btarget)
| IClose : forall tag afree bfree,
        Forall2 I_expr afree bfree ->
        I_expr (A.Close tag afree) (B.Close tag bfree)
.

Inductive I : A.state -> B.state -> Prop :=
| IRun : forall ae al ak be bl bk,
        I_expr ae be ->
        Forall A.value al ->
        Forall B.value bl ->
        Forall2 I_expr al bl ->
        (forall av bv,
            A.value av ->
            B.value bv ->
            I_expr av bv ->
            I (ak av) (bk bv)) ->
        I (A.Run ae al ak) (B.Run be bl bk)

| IStop : forall ae be,
        I_expr ae be ->
        I (A.Stop ae) (B.Stop be).



Lemma I_expr_value : forall a b,
    I_expr a b ->
    A.value a ->
    B.value b.
induction a using A.expr_ind''; intros0 II Aval; invc Aval; invc II.
- constructor. list_magic_on (args, (bargs, tt)).
- constructor. list_magic_on (free, (bfree, tt)).
Qed.
Hint Resolve I_expr_value.

Lemma I_expr_value' : forall b a,
    I_expr a b ->
    B.value b ->
    A.value a.
induction b using B.expr_ind''; intros0 II Bval; invc Bval; invc II.
- constructor. list_magic_on (args, (aargs, tt)).
- constructor. list_magic_on (free, (afree, tt)).
Qed.

Lemma I_expr_not_value : forall a b,
    I_expr a b ->
    ~A.value a ->
    ~B.value b.
intros. intro. fwd eapply I_expr_value'; eauto.
Qed.
Hint Resolve I_expr_not_value.

Lemma I_expr_not_value' : forall a b,
    I_expr a b ->
    ~B.value b ->
    ~A.value a.
intros. intro. fwd eapply I_expr_value; eauto.
Qed.

Lemma Forall_I_expr_value : forall aes bes,
    Forall2 I_expr aes bes ->
    Forall A.value aes ->
    Forall B.value bes.
intros. list_magic_on (aes, (bes, tt)).
Qed.
Hint Resolve Forall_I_expr_value.



(* compile_elims_match *)

Lemma emit_extend : forall x s x' s',
    emit x s = (x', s') ->
    exists s'', s' = s ++ s''.
intros0 Hemit. unfold emit in *. invc Hemit.  eauto.
Qed.

Lemma compile_extend : forall ae s be' s',
    compile ae s = (be', s') ->
    exists s'', s' = s ++ s''.
induction ae using A.expr_ind''; intros0 Hcomp;
simpl in Hcomp; refold_compile; break_bind_state.

- exists []. eauto using app_nil_r.

- exists []. eauto using app_nil_r.

- destruct (IHae1 ?? ?? ?? **) as [s''1 ?].
  destruct (IHae2 ?? ?? ?? **) as [s''2 ?].
  exists (s''1 ++ s''2). subst. eauto using app_assoc.

- generalize dependent s'. generalize dependent x. generalize dependent s.
  induction args; intros.
  + simpl in *. break_bind_state.
    exists []. eauto using app_nil_r.
  + simpl in *. break_bind_state.
    on (Forall _ (_ :: _)), invc.
    destruct (H2 ?? ?? ?? **) as [s''1 ?].
    destruct (IHargs ** ?? ?? ?? **) as [s''2 ?].
    exists (s''1 ++ s''2). subst. eauto using app_assoc.

- assert (HH : exists s''1, s0 = s ++ s''1). {
    clear Heqp0 Heqp1 Heqp2.
    generalize dependent s0. generalize dependent x. generalize dependent s.
    induction cases; intros; simpl in *; break_bind_state.
    - exists []. eauto using app_nil_r.
    - on (Forall _ (_ :: _)), invc.
      destruct a; simpl in *; break_bind_state.
      destruct (H2 ?? ?? ?? **) as [s''1 ?].
      destruct (IHcases ** ?? ?? ?? **) as [s''2 ?].
      exists (s''1 ++ s''2). subst. eauto using app_assoc.
  }
  destruct HH as [s''1 ?].
  destruct (IHae ?? ?? ?? **) as [s''2 ?].
  on (get_next _ = _), invc.
  destruct (emit_extend ?? ?? ?? ?? **) as [s''3 ?].
  exists (s''1 ++ s''2 ++ s''3). subst. repeat rewrite app_assoc. reflexivity.

- generalize dependent s'. generalize dependent x. generalize dependent s.
  induction free; intros.
  + simpl in *. break_bind_state.
    exists []. eauto using app_nil_r.
  + simpl in *. break_bind_state.
    on (Forall _ (_ :: _)), invc.
    destruct (H2 ?? ?? ?? **) as [s''1 ?].
    destruct (IHfree ** ?? ?? ?? **) as [s''2 ?].
    exists (s''1 ++ s''2). subst. eauto using app_assoc.

Qed.

Lemma compile_list_extend : forall aes s bes' s',
    compile_list aes s = (bes', s') ->
    exists s'', s' = s ++ s''.
induction aes; intros0 Hcomp;
simpl in *; refold_compile; break_bind_state.
- exists []. eauto using app_nil_r.
- destruct (compile_extend ?? ?? ?? ?? **) as [s''1 ?].
  destruct (IHaes ?? ?? ?? **) as [s''2 ?].
  exists (s''1 ++ s''2). subst. eauto using app_assoc.
Qed.

Lemma compile_pair_extend : forall ap s bp' s',
    compile_pair ap s = (bp', s') ->
    exists s'', s' = s ++ s''.
intros0 Hcomp. destruct ap. simpl in *. break_bind_state.
eapply compile_extend. eauto.
Qed.

Lemma compile_list_pair_extend : forall aps s bps' s',
    compile_list_pair aps s = (bps', s') ->
    exists s'', s' = s ++ s''.
induction aps; intros0 Hcomp;
simpl in *; refold_compile; break_bind_state.
- exists []. eauto using app_nil_r.
- destruct (compile_pair_extend ?? ?? ?? ?? **) as [s''1 ?].
  destruct (IHaps ?? ?? ?? **) as [s''2 ?].
  exists (s''1 ++ s''2). subst. eauto using app_assoc.
Qed.

Lemma compile_elims_match : forall ae be elims elims',
    compile ae elims = (be, elims') ->
    B.elims_match elims' be.
induction ae using A.expr_rect_mut with
    (Pl := fun aes => forall bes elims elims',
        compile_list aes elims = (bes, elims') ->
        Forall (B.elims_match elims') bes)
    (Pp := fun ap => forall bp elims elims',
        compile_pair ap elims = (bp, elims') ->
        B.elims_match elims' (fst bp))
    (Plp := fun aps => forall bps elims elims',
        compile_list_pair aps elims = (bps, elims') ->
        Forall (fun p => B.elims_match elims' (fst p)) bps);
intros0 Hcomp; simpl in Hcomp; refold_compile; break_bind_state.

(* compile *)

- constructor.
- constructor.

- simpl.
  fwd eapply compile_extend with (ae := ae2) as HH; eauto.  destruct HH.
  subst. split.
  + eapply B.elims_match_extend. eauto.
  + eauto.

- simpl. B.refold_elims_match elims'.
  rewrite B.elims_match_list_Forall. eauto.

- simpl. B.refold_elims_match elims'.
  on (emit _ _ = _), invc.
  on (get_next _ = _), invc.
  fwd eapply compile_extend as HH; eauto.  destruct HH.
  subst. split; [|split].
  + rewrite nth_error_app2 by eauto.
    replace (length _ - length _) with 0 by omega.
    reflexivity.
  + rewrite B.elims_match_list_pair_Forall'.
    specialize (IHae ?? ?? ?? **).
    list_magic_on (x, tt).  eauto using B.elims_match_extend.
  + specialize (IHae0 ?? ?? ?? **).
    eauto using B.elims_match_extend.

- simpl. B.refold_elims_match elims'.
  rewrite B.elims_match_list_Forall. eauto.

(* compile_list *)

- constructor.

- fwd eapply compile_list_extend with (aes := es) as HH; eauto.  destruct HH.
  subst. constructor.
  + eapply B.elims_match_extend. eauto.
  + eauto.

(* compile_pair *)

- simpl. eauto.

(* compile_list_pair *)

- constructor.

- fwd eapply compile_list_pair_extend with (aps := ps) as HH; eauto.  destruct HH.
  subst. constructor.
  + eapply B.elims_match_extend. eauto.
  + eauto.

Qed.

Lemma compile_list_elims_match : forall ae be elims elims',
    compile_list ae elims = (be, elims') ->
    Forall (B.elims_match elims') be.
induction ae; intros0 Hcomp; simpl in *; break_bind_state.

- constructor.

- fwd eapply compile_list_extend as HH; eauto.  destruct HH.
  subst. constructor.
  + eapply B.elims_match_extend. eauto using compile_elims_match.
  + eauto.
Qed.

Theorem compile_cu_elims_match : forall a ameta b bmeta belims bnames,
    compile_cu (a, ameta) = (b, bmeta, belims, bnames) ->
    Forall (B.elims_match belims) b.
intros0 Hcomp; simpl in *. repeat (break_match; []). subst. inject_pair.
eauto using compile_list_elims_match.
Qed.

Theorem compile_cu_elims_match' : forall a b,
    compile_cu a = b ->
    Forall (B.elims_match (snd (fst b))) (fst (fst (fst b))).
intros. repeat on >@prod, fun H => destruct H.
eauto using compile_cu_elims_match.
Qed.



(* compile_I_expr *)

Theorem compile_I_expr : forall ae be s s',
    compile ae s = (be, s') ->
    I_expr ae be.
induction ae using A.expr_rect_mut with
    (Pl := fun aes => forall bes s s',
        compile_list aes s = (bes, s') ->
        Forall2 I_expr aes bes)
    (Pp := fun ap => forall bp s s',
        compile_pair ap s = (bp, s') ->
        I_expr (fst ap) (fst bp) /\ snd ap = snd bp)
    (Plp := fun aps => forall bps s s',
        compile_list_pair aps s = (bps, s') ->
        Forall2 (fun ap bp => I_expr (fst ap) (fst bp) /\ snd ap = snd bp) aps bps);
intros0 Hcomp;
simpl in Hcomp; refold_compile; try rewrite <- Hcomp in *;
break_bind_state; try solve [eauto | econstructor; eauto].
Qed.

Lemma compile_list_I_expr :
  forall l i1 l' i2,
    compile_list l i1 = (l',i2) ->
    Forall2 I_expr l l'.
Proof.
  induction l; intros; simpl in *.
  unfold ret_state in H. inv H. econstructor; eauto.
  unfold seq in *.
  unfold bind_state in *.
  break_match_hyp; try congruence.
  unfold fmap in *.
  break_match_hyp; try congruence.
  break_match_hyp; try congruence.
  unfold ret_state in *. inv Heqp.
  inv H.
  econstructor; eauto.
  eapply compile_I_expr; eauto.
Qed.


(* I_sim *)

Ltac i_ctor := intros; constructor; eauto.
Ltac i_lem H := intros; eapply H; eauto.

Lemma unroll_sim : forall rec,
    forall acase aargs amk_rec ae',
    forall bcase bargs bmk_rec,
    A.unroll_elim acase aargs rec amk_rec = Some ae' ->
    I_expr acase bcase ->
    Forall2 I_expr aargs bargs ->
    (forall av bv,
        I_expr av bv ->
        I_expr (amk_rec av) (bmk_rec bv)) ->
    exists be',
        B.unroll_elim bcase bargs rec bmk_rec = Some be' /\
        I_expr ae' be'.
first_induction aargs; destruct rec; intros0 Aunroll IIcase IIargs IImk_rec;
try discriminate; on (Forall2 _ _ bargs), invc.

- simpl in *. inject_some.
  eexists. eauto.

- simpl in *. destruct b.
  + eapply IHaargs; eauto.
    i_ctor. i_ctor.
  + eapply IHaargs; eauto.
    i_ctor.
Qed.


Theorem I_sim : forall AE BE a a' b,
    Forall2 I_expr AE BE ->
    I a b ->
    A.sstep AE a a' ->
    exists b',
        B.sstep BE b b' /\
        I a' b'.

destruct a as [ae al ak | ae];
intros0 Henv II Astep; [ | solve [invc Astep] ].

inv Astep; invc II; try on (I_expr _ _), invc.

- fwd eapply Forall2_nth_error_ex with (xs := al) (ys := bl); eauto.
    break_exists. break_and.
  assert (A.value v).  { eapply Forall_nth_error; eauto. }

  eexists. split. eapply B.SArg; eauto.
  on _, eapply_; eauto.

- fwd eapply Forall2_nth_error_ex with (xs := al) (ys := bl); eauto.
    break_exists. break_and.
  assert (A.value v).  { eapply Forall_nth_error; eauto. }

  eexists. split. eapply B.SUpVar; eauto.
  on _, eapply_; eauto.

- on _, invc_using Forall2_3part_inv.

  eexists. split. eapply B.SCloseStep; eauto.
  i_ctor. i_ctor. i_ctor. eauto using Forall2_app.

- eexists. split. eapply B.SCloseDone; eauto.
  on _, eapply_; eauto.
  all: constructor; eauto.

- on _, invc_using Forall2_3part_inv.

  eexists. split. eapply B.SConstrStep; eauto.
  i_ctor. i_ctor. i_ctor. eauto using Forall2_app.

- eexists. split. eapply B.SConstrDone; eauto.
  on _, eapply_; eauto.
  all: constructor; eauto.

- eexists. split. eapply B.SCallL; eauto.
  i_ctor. i_ctor. i_ctor.

- eexists. split. eapply B.SCallR; eauto.
  i_ctor. i_ctor. i_ctor.

- fwd eapply Forall2_nth_error_ex with (xs := AE) (ys := BE) as HH; eauto.
    destruct HH as (bbody & ? & ?).
  on (I_expr (A.Close _ _) _), invc.

  eexists. split. eapply B.SMakeCall; eauto.
  i_ctor.

- eexists. split. eapply B.SElimNStep; eauto.
  i_ctor. i_ctor. i_ctor.

- fwd eapply Forall2_nth_error_ex with (xs := cases) (ys := bcases) as HH; eauto.
    destruct HH as ([bcase brec] & ? & ? & ?). simpl in *.
    subst brec.
  on (I_expr _ btarget), invc.
  fwd eapply unroll_sim as HH; eauto.  { i_ctor. }
    break_exists. break_and.

  eexists. split. eapply B.SEliminate; eauto.
  i_ctor.
Qed.



Check compile_cu.

Lemma compile_cu_I_expr : forall A Ameta B Bmeta Belims Belim_names,
    compile_cu (A, Ameta) = (B, Bmeta, Belims, Belim_names) ->
    Forall2 I_expr A B.
intros0 Hcomp. unfold compile_cu in *. repeat break_match. subst. inject_pair.
simpl. eauto using compile_list_I_expr.
Qed.

Lemma compile_cu_metas : forall A Ameta B Bmeta Belims Belim_names,
    compile_cu (A, Ameta) = (B, Bmeta, Belims, Belim_names) ->
    Ameta = Bmeta.
simpl. intros. repeat break_match. subst. inject_pair. auto.
Qed.

Lemma expr_value_I_expr : forall be v,
    B.expr_value be v ->
    exists ae,
        A.expr_value ae v /\
        I_expr ae be.
make_first v. intros v. revert v.
mut_induction v using value_rect_mut' with
    (Pl := fun vs => forall bes,
        Forall2 B.expr_value bes vs ->
        exists aes,
            Forall2 A.expr_value aes vs /\
            Forall2 I_expr aes bes);
[intros0 Hev; invc Hev.. | ].

- destruct (IHv ?? **) as (? & ? & ?).
  eauto using A.EvConstr, IConstr.

- destruct (IHv ?? **) as (? & ? & ?).
  eauto using A.EvClose, IClose.

- eauto.

- destruct (IHv ?? **) as (? & ? & ?).
  destruct (IHv0 ?? **) as (? & ? & ?).
  eauto.

- finish_mut_induction expr_value_I_expr using list.
Qed exporting.

Lemma expr_value_I_expr' : forall ae be v,
    A.expr_value ae v ->
    I_expr ae be ->
    B.expr_value be v.
induction ae using A.expr_rect_mut with
    (Pl := fun ae => forall be v,
        Forall2 A.expr_value ae v ->
        Forall2 I_expr ae be ->
        Forall2 B.expr_value be v)
    (Pp := fun ap => forall be v,
        A.expr_value (fst ap) v ->
        I_expr (fst ap) be ->
        B.expr_value be v)
    (Plp := fun aps => forall bes vs,
        Forall2 (fun ap v => A.expr_value (fst ap) v) aps vs ->
        Forall2 (fun ap be => I_expr (fst ap) be) aps bes ->
        Forall2 (fun be v => B.expr_value be v) bes vs);
intros0 Hae II; try solve [invc Hae; invc II; econstructor; eauto | simpl in *; eauto].
Qed.




Require Import oeuf.Semantics.

Section Preservation.

    Variable aprog : A.prog_type.
    Variable bprog : B.prog_type.

    Hypothesis Hcomp : compile_cu aprog = bprog.

    Theorem fsim : Semantics.forward_simulation (A.semantics aprog) (B.semantics bprog).
    destruct aprog as [A Ameta], bprog as [[[B Bmeta] Belims] Belim_names].
    fwd eapply compile_cu_I_expr; eauto.
    fwd eapply compile_cu_metas; eauto.

    eapply Semantics.forward_simulation_step with
        (match_states := I)
        (match_values := @eq value).

    - simpl. intros0 Bcall Hf Ha. invc Bcall.

      fwd eapply Forall2_nth_error_ex' with (ys := B) as HH; eauto.
        destruct HH as (abody & ? & ?).
      fwd eapply expr_value_I_expr as HH; eauto. destruct HH as (? & ? & ?).
      fwd eapply expr_value_I_expr_list as HH; eauto. destruct HH as (? & ? & ?).

      eexists. split.
      + econstructor. 4: eauto.
        all: eauto using A.expr_value_value, A.expr_value_value_list.
        i_ctor.
      + i_ctor.

    - simpl. intros0 II Afinal. invc Afinal. invc II.
      fwd eapply expr_value_I_expr'; eauto.
      (*fwd eapply I_expr_expr_value; eauto.*)

      eexists. split. i_ctor. auto.

    - intros0 Astep. intros0 II.
      i_lem I_sim.
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
