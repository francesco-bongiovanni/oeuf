(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2016     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(** This module centralizes the notions of hooks. Hooks are pointers that are to
    be set at runtime exactly once. *)

type 'a t
(** The type of hooks containing ['a]. Hooks can only be set. *)

type 'a value
(** The content part of a hook. *)

val make : ?default:'a -> unit -> ('a value * 'a t)
(** Create a new hook together with a way to retrieve its runtime value. *)

val get : 'a value -> 'a
(** Access the content of a hook. If it was not set yet, try to recover the
    default value if there is one.
    @raise Assert_failure if undefined. *)

val set : 'a t -> 'a -> unit
(** Register a hook. Assertion failure if already registered. *)
