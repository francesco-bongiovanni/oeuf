Require Import Common.
Require Import Utopia.

Require Import Metadata.
Require Import Semantics.
Require Import HighestValues.

Require Export Untyped4.



(* the actual step relation *)
Inductive sstep (g : list expr) : state -> state -> Prop :=
| SArg : forall (l : list value) (k : cont) v,
        nth_error l 0 = Some v ->
        sstep g (Run (Arg) l k)
                (run_cont k v)

| SUpVar : forall idx (l : list value) (k : cont) v,
        nth_error l (S idx) = Some v ->
        sstep g (Run (UpVar idx) l k)
                (run_cont k v)

| SAppL : forall (e1 : expr) (e2 : expr) l k,
        ~ is_value e1 ->
        sstep g (Run (App e1 e2) l k)
                (Run e1 l (KAppL e2 l k))

| SAppR : forall (e1 : expr) (e2 : expr) l k,
        is_value e1 ->
        ~ is_value e2 ->
        sstep g (Run (App e1 e2) l k)
                (Run e2 l (KAppR e1 l k))

| SMakeCall : forall fname free arg l k body,
        nth_error g fname = Some body ->
        sstep g (Run (App (Value (Close fname free)) (Value arg)) l k)
                (Run body (arg :: free) k)

| SConstrStep : forall
            (ctor : constr_name)
            (vs : list expr)
            (e : expr)
            (es : list expr)
            l k,
        Forall is_value vs ->
        ~ is_value e ->
        sstep g (Run (MkConstr ctor (vs ++ e :: es)) l k)
                (Run e l (KConstr ctor vs es l k))

| SConstrDone : forall
            (ctor : constr_name)
            (vs : list value)
            l k,
        let es := map Value vs in
        sstep g (Run (MkConstr ctor es) l k)
                (run_cont k (Constr ctor vs))

| SCloseStep : forall
            (fname : nat)
            (vs : list expr)
            (e : expr)
            (es : list expr)
            l k,
        Forall is_value vs ->
        ~ is_value e ->
        sstep g (Run (MkClose fname (vs ++ e :: es)) l k)
                (Run e l (KClose fname vs es l k))

| SCloseDone : forall
            (fname : nat)
            (vs : list value)
            l k,
        let es := map Value vs in
        sstep g (Run (MkClose fname es) l k)
                (run_cont k (Close fname vs))

| SElimTarget : forall
            (ty : type_name)
            (cases : list expr)
            (target : expr)
            l k,
        ~ is_value target ->
        sstep g (Run (Elim ty cases target) l k)
                (Run target l (KElim ty cases l k))

| SEliminate : forall
            (ty : type_name)
            (cases : list expr)
            (ctor : constr_name)
            (args : list value)
            (case : expr)
            (result : expr)
            l k,
        is_ctor_for_type ty ctor ->
        constructor_arg_n ctor = length args ->
        nth_error cases (constructor_index ctor) = Some case ->
        unroll_elim case ctor args (Elim ty cases) = result ->
        sstep g (Run (Elim ty cases (Value (Constr ctor args))) l k)
                (Run result l k)
.
