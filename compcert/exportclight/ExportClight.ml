(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the GNU General Public License as published by  *)
(*  the Free Software Foundation, either version 2 of the License, or  *)
(*  (at your option) any later version.  This file is also distributed *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** Export Clight as a Coq file *)

open Format
open Camlcoq
open Datatypes
open Values
open AST
open Ctypes
open Cop
open Clight

(* Options, lists, pairs *)

let print_option fn p = function
  | None -> fprintf p "None"
  | Some x -> fprintf p "(Some %a)" fn x

let print_pair fn1 fn2 p (x1, x2) =
  fprintf p "@[<hov 1>(%a,@ %a)@]" fn1 x1 fn2 x2

let print_list fn p l =
  match l with
  | [] ->
      fprintf p "nil"
  | hd :: tl ->
      fprintf p "@[<hov 1>(";
      let rec plist = function
      | [] -> fprintf p "nil"
      | hd :: tl -> fprintf p "%a ::@ " fn hd; plist tl
      in plist l;
      fprintf p ")@]"

(* Identifiers *)

exception Not_an_identifier

let sanitize s =
  let s' = String.create (String.length s) in
  for i = 0 to String.length s - 1 do
    s'.[i] <-
      match s.[i] with
      | 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' as c -> c
      | ' ' | '$' -> '_'
      | _ -> raise Not_an_identifier
  done;
  s'

module StringSet = Set.Make(String)

let temp_names : (ident, string) Hashtbl.t = Hashtbl.create 17
let all_temp_names : StringSet.t ref = ref StringSet.empty

let ident p id =
  try
    let s = Hashtbl.find string_of_atom id in
    fprintf p "_%s" (sanitize s)
  with Not_found | Not_an_identifier ->
  try
    let s = Hashtbl.find temp_names id in
    fprintf p "%s" s
  with Not_found ->
    fprintf p "%ld%%positive" (P.to_int32 id)

let define_idents p =
  Hashtbl.iter
    (fun id name ->
      try
        fprintf p "Definition _%s : ident := %ld%%positive.@ "
                  (sanitize name) (P.to_int32 id)
      with Not_an_identifier ->
        ())
    string_of_atom;
  Hashtbl.iter
    (fun id name ->
      fprintf p "Definition %s : ident := %ld%%positive.@ "
                name (P.to_int32 id))
    temp_names;
  fprintf p "@ "

let rec find_temp_name name counter =
  let name' =
    if counter = 0 then name ^ "'" else sprintf "%s'%d" name counter in
  if StringSet.mem name' !all_temp_names
  then find_temp_name name (counter + 1)
  else name'

let name_temporary t v =
  (* Try to give "t" a name that is the name of "v" with a prime
     plus a number to disambiguate if needed. *)
  if not (Hashtbl.mem string_of_atom t || Hashtbl.mem temp_names t) then begin
    try
      let vname = "_" ^ sanitize (Hashtbl.find string_of_atom v) in
      let tname = find_temp_name vname 0 in
      Hashtbl.add temp_names t tname;
      all_temp_names := StringSet.add tname !all_temp_names
    with Not_found | Not_an_identifier ->
      ()
  end

(* Numbers *)

let coqint p n =
  let n = camlint_of_coqint n in
  if n >= 0l
  then fprintf p "(Int.repr %ld)" n
  else fprintf p "(Int.repr (%ld))" n

let coqint64 p n =
  let n = camlint64_of_coqint n in
  if n >= 0L
  then fprintf p "(Int64.repr %Ld)" n
  else fprintf p "(Int64.repr (%Ld))" n

let coqfloat p n =
  fprintf p "(Float.of_bits %a)" coqint64 (Floats.Float.to_bits n)

let coqsingle p n =
  fprintf p "(Float32.of_bits %a)" coqint (Floats.Float32.to_bits n)

let coqN p n =
  fprintf p "%ld%%N" (N.to_int32 n)

(* Coq strings *)

let coqstring p s =
  fprintf p "\"%s\"" (camlstring_of_coqstring s)

(* Raw attributes *)

let attribute p a =
  if a = noattr then
    fprintf p "noattr"
  else
    fprintf p "{| attr_volatile := %B; attr_alignas := %a |}"
              a.attr_volatile
              (print_option coqN) a.attr_alignas

(* Types *)

let rec typ p t =
  match attr_of_type t with
  | { attr_volatile = false; attr_alignas = None} ->
        rtyp p t
  | { attr_volatile = true; attr_alignas = None} ->
        fprintf p "(tvolatile %a)" rtyp t
  | { attr_volatile = false; attr_alignas = Some n} ->
        fprintf p "(talignas %a %a)" coqN n rtyp t
  | { attr_volatile = true; attr_alignas = Some n} ->
        fprintf p "(tvolatile_alignas %a %a)" coqN n rtyp t

and rtyp p = function
  | Tvoid -> fprintf p "tvoid"
  | Tint(sz, sg, _) ->
      fprintf p "%s" (
        match sz, sg with
        | I8, Signed -> "tschar"
        | I8, Unsigned -> "tuchar"
        | I16, Signed -> "tshort"
        | I16, Unsigned -> "tushort"
        | I32, Signed -> "tint"
        | I32, Unsigned -> "tuint"
        | IBool, _ -> "tbool")
  | Tlong(sg, _) ->
      fprintf p "%s" (
        match sg with
        | Signed -> "tlong"
        | Unsigned -> "tulong")
  | Tfloat(sz, _) ->
      fprintf p "%s" (
        match sz with
        | F32 -> "tfloat"
        | F64 -> "tdouble")
  | Tpointer(t, _) ->
      fprintf p "(tptr %a)" typ t
  | Tarray(t, sz, _) ->
      fprintf p "(tarray %a %ld)" typ t (Z.to_int32 sz)
  | Tfunction(targs, tres, cc) ->
      fprintf p "@[<hov 2>(Tfunction@ %a@ %a@ %a)@]"
                typlist targs typ tres callconv cc
  | Tstruct(id, _) ->
      fprintf p "(Tstruct %a noattr)" ident id
  | Tunion(id, _) ->
      fprintf p "(Tunion %a noattr)" ident id

and typlist p = function
  | Tnil ->
      fprintf p "Tnil"
  | Tcons(t, tl) ->
      fprintf p "@[<hov 2>(Tcons@ %a@ %a)@]" typ t typlist tl

and callconv p cc =
  if cc = cc_default
  then fprintf p "cc_default"
  else fprintf p "{|cc_vararg:=%b; cc_unproto:=%b; cc_structret:=%b|}"
                  cc.cc_vararg cc.cc_unproto cc.cc_structret

(* External functions *)

let asttype p t =
  fprintf p "%s"
     (match t with
      | AST.Tint -> "AST.Tint"
      | AST.Tfloat -> "AST.Tfloat"
      | AST.Tlong -> "AST.Tlong"
      | AST.Tsingle -> "AST.Tsingle"
      | AST.Tany32 -> "AST.Tany32"
      | AST.Tany64 -> "AST.Tany64")

let name_of_chunk = function
  | Mint8signed -> "Mint8signed"
  | Mint8unsigned -> "Mint8unsigned"
  | Mint16signed -> "Mint16signed"
  | Mint16unsigned -> "Mint16unsigned"
  | Mint32 -> "Mint32"
  | Mint64 -> "Mint64"
  | Mfloat32 -> "Mfloat32"
  | Mfloat64 -> "Mfloat64"
  | Many32 -> "Many32"
  | Many64 -> "Many64"

let signatur p sg =
  fprintf p "@[<hov 2>(mksignature@ %a@ %a@ %a)@]"
     (print_list asttype) sg.sig_args
     (print_option asttype) sg.sig_res
     callconv sg.sig_cc

let assertions = ref ([]: (string * typ list) list)

let external_function p = function
  | EF_external(name, sg) ->
      fprintf p "@[<hov 2>(EF_external %a@ %a)@]" coqstring name signatur sg
  | EF_builtin(name, sg) ->
      fprintf p "@[<hov 2>(EF_builtin %a@ %a)@]" coqstring name signatur sg
  | EF_vload chunk ->
      fprintf p "(EF_vload %s)" (name_of_chunk chunk)
  | EF_vstore chunk ->
      fprintf p "(EF_vstore %s)" (name_of_chunk chunk)
  | EF_malloc -> fprintf p "EF_malloc"
  | EF_free -> fprintf p "EF_free"
  | EF_memcpy(sz, al) ->
      fprintf p "(EF_memcpy %ld %ld)" (Z.to_int32 sz) (Z.to_int32 al)
  | EF_annot(text, targs) ->
      assertions := (camlstring_of_coqstring text, targs) :: !assertions;
      fprintf p "(EF_annot %a %a)" coqstring text (print_list asttype) targs
  | EF_annot_val(text, targ) ->
      assertions := (camlstring_of_coqstring text, [targ]) :: !assertions;
      fprintf p "(EF_annot_val %a %a)" coqstring text asttype targ
  | EF_debug(kind, text, targs) ->
      fprintf p "(EF_debug %ld%%positive %ld%%positive %a)" (P.to_int32 kind) (P.to_int32 text) (print_list asttype) targs
  | EF_inline_asm(text, sg, clob) ->
      fprintf p "@[<hov 2>(EF_inline_asm %a@ %a@ %a)@]"
              coqstring text
              signatur sg
              (print_list coqstring) clob

(* Expressions *)

let name_unop = function
  | Onotbool -> "Onotbool"
  | Onotint -> "Onotint"
  | Oneg -> "Oneg"
  | Oabsfloat -> "Oabsfloat"

let name_binop = function
  | Oadd -> "Oadd"
  | Osub -> "Osub"
  | Omul -> "Omul"
  | Odiv -> "Odiv"
  | Omod -> "Omod"
  | Oand -> "Oand"
  | Oor -> "Oor"
  | Oxor -> "Oxor"
  | Oshl -> "Oshl"
  | Oshr -> "Oshr"
  | Oeq -> "Oeq"
  | One -> "One"
  | Olt -> "Olt"
  | Ogt -> "Ogt"
  | Ole -> "Ole"
  | Oge -> "Oge"

let rec expr p = function
  | Evar(id, t) ->
      fprintf p "(Evar %a %a)" ident id typ t
  | Etempvar(id, t) ->
      fprintf p "(Etempvar %a %a)" ident id typ t
  | Ederef(a1, t) ->
      fprintf p "@[<hov 2>(Ederef@ %a@ %a)@]" expr a1 typ t
  | Efield(a1, f, t) ->
      fprintf p "@[<hov 2>(Efield@ %a@ %a@ %a)@]" expr a1 ident f typ t
  | Econst_int(n, t) ->
      fprintf p "(Econst_int %a %a)" coqint n typ t
  | Econst_float(n, t) ->
      fprintf p "(Econst_float %a %a)" coqfloat n typ t
  | Econst_long(n, t) ->
      fprintf p "(Econst_long %a %a)" coqint64 n typ t
  | Econst_single(n, t) ->
      fprintf p "(Econst_single %a %a)" coqsingle n typ t
  | Eunop(op, a1, t) ->
      fprintf p "@[<hov 2>(Eunop %s@ %a@ %a)@]"
         (name_unop op) expr a1 typ t
  | Eaddrof(a1, t) ->
      fprintf p "@[<hov 2>(Eaddrof@ %a@ %a)@]" expr a1 typ t
  | Ebinop(op, a1, a2, t) ->
      fprintf p "@[<hov 2>(Ebinop %s@ %a@ %a@ %a)@]"
         (name_binop op) expr a1 expr a2 typ t
  | Ecast(a1, t) ->
      fprintf p "@[<hov 2>(Ecast@ %a@ %a)@]" expr a1 typ t
  | Esizeof(t1, t) ->
      fprintf p "(Esizeof %a %a)" typ t1 typ t
  | Ealignof(t1, t) ->
      fprintf p "(Ealignof %a %a)" typ t1 typ t

(* Statements *)

let rec stmt p = function
  | Sskip ->
      fprintf p "Sskip"
  | Sassign(e1, e2) ->
      fprintf p "@[<hov 2>(Sassign@ %a@ %a)@]" expr e1 expr e2
  | Sset(id, e2) ->
      fprintf p "@[<hov 2>(Sset %a@ %a)@]" ident id expr e2
  | Scall(optid, e1, el) ->
      fprintf p "@[<hov 2>(Scall %a@ %a@ %a)@]"
        (print_option ident) optid expr e1 (print_list expr) el
  | Sbuiltin(optid, ef, tyl, el) ->
      fprintf p "@[<hov 2>(Sbuiltin %a@ %a@ %a@ %a)@]"
        (print_option ident) optid
        external_function ef
        typlist tyl
        (print_list expr) el
  | Ssequence(Sskip, s2) ->
      stmt p s2
  | Ssequence(s1, Sskip) ->
      stmt p s1
  | Ssequence(s1, s2) ->
      fprintf p "@[<hv 2>(Ssequence@ %a@ %a)@]" stmt s1 stmt s2
  | Sifthenelse(e, s1, s2) ->
      fprintf p "@[<hv 2>(Sifthenelse %a@ %a@ %a)@]" expr e stmt s1 stmt s2
  | Sloop (Ssequence (Sifthenelse(e, Sskip, Sbreak), s), Sskip) ->
      fprintf p "@[<hv 2>(Swhile@ %a@ %a)@]" expr e stmt s
  | Sloop (Ssequence (Ssequence(Sskip, Sifthenelse(e, Sskip, Sbreak)), s), Sskip) ->
      fprintf p "@[<hv 2>(Swhile@ %a@ %a)@]" expr e stmt s
  | Sloop(s1, s2) ->
      fprintf p "@[<hv 2>(Sloop@ %a@ %a)@]" stmt s1 stmt s2
  | Sbreak ->
      fprintf p "Sbreak"
  | Scontinue ->
      fprintf p "Scontinue"
  | Sswitch(e, cases) ->
      fprintf p "@[<hv 2>(Sswitch %a@ %a)@]" expr e lblstmts cases
  | Sreturn e ->
      fprintf p "@[<hv 2>(Sreturn %a)@]" (print_option expr) e
  | Slabel(lbl, s1) ->
      fprintf p "@[<hv 2>(Slabel %a@ %a)@]" ident lbl stmt s1
  | Sgoto lbl ->
      fprintf p "(Sgoto %a)" ident lbl

and lblstmts p = function
  | LSnil ->
      ()
  | LScons(lbl, s, ls) ->
      fprintf p "@[<hv 2>(LScase %a@ %a@ %a)@]"
              (print_option coqint) lbl stmt s lblstmts ls

let print_function p (id, f) =
  fprintf p "Definition f_%s := {|@ " (extern_atom id);
  fprintf p "  fn_return := %a;@ " typ f.fn_return;
  fprintf p "  fn_callconv := %a;@ " callconv f.fn_callconv;
  fprintf p "  fn_params := %a;@ " (print_list (print_pair ident typ)) f.fn_params;
  fprintf p "  fn_vars := %a;@ " (print_list (print_pair ident typ)) f.fn_vars;
  fprintf p "  fn_temps := %a;@ " (print_list (print_pair ident typ)) f.fn_temps;
  fprintf p "  fn_body :=@ ";
  stmt p f.fn_body;
  fprintf p "@ |}.@ @ "

let init_data p = function
  | Init_int8 n -> fprintf p "Init_int8 %a" coqint n
  | Init_int16 n -> fprintf p "Init_int16 %a" coqint n
  | Init_int32 n -> fprintf p "Init_int32 %a" coqint n
  | Init_int64 n -> fprintf p "Init_int64 %a" coqint64 n
  | Init_float32 n -> fprintf p "Init_float32 %a" coqsingle n
  | Init_float64 n -> fprintf p "Init_float64 %a" coqfloat n
  | Init_space n -> fprintf p "Init_space %ld" (Z.to_int32 n)
  | Init_addrof(id,ofs) -> fprintf p "Init_addrof %a %a" ident id coqint ofs

let print_variable p (id, v) =
  fprintf p "Definition v_%s := {|@ " (extern_atom id);
  fprintf p "  gvar_info := %a;@ " typ v.gvar_info;
  fprintf p "  gvar_init := %a;@ " (print_list init_data) v.gvar_init;
  fprintf p "  gvar_readonly := %B;@ " v.gvar_readonly;
  fprintf p "  gvar_volatile := %B@ " v.gvar_volatile;
  fprintf p "|}.@ @ "

let print_globdef p (id, gd) =
  match gd with
  | Gfun(Internal f) -> print_function p (id, f)
  | Gfun(External _) -> ()
  | Gvar v -> print_variable p (id, v)

let print_ident_globdef p = function
  | (id, Gfun(Internal f)) ->
      fprintf p "(%a, Gfun(Internal f_%s))" ident id (extern_atom id)
  | (id, Gfun(External(ef, targs, tres, cc))) ->
      fprintf p "@[<hov 2>(%a,@ @[<hov 2>Gfun(External %a@ %a@ %a@ %a))@]@]"
        ident id external_function ef typlist targs typ tres callconv cc
  | (id, Gvar v) ->
      fprintf p "(%a, Gvar v_%s)" ident id (extern_atom id)

(* Composite definitions *)

let print_composite_definition p (Composite(id, su, m, a)) =
  fprintf p "@[<hv 2>Composite %a %s@ %a@ %a@]"
    ident id
    (match su with Struct -> "Struct" | Union -> "Union")
    (print_list (print_pair ident typ)) m
    attribute a

(* Assertion processing *)

let re_annot_param = Str.regexp "%%\\|%[1-9][0-9]*"

type fragment = Text of string | Param of int

(* For compatibility with OCaml < 4.00 *)
let list_iteri f l =
  let rec iteri i = function
  | [] -> ()
  | a::l -> f i a; iteri (i + 1) l
  in iteri 0 l

let print_assertion p (txt, targs) =
  let frags =
    List.map
      (function
       | Str.Text s -> Text s
       | Str.Delim "%%" -> Text "%"
       | Str.Delim s -> Param(int_of_string(String.sub s 1 (String.length s - 1))))
      (Str.full_split re_annot_param txt) in
  let max_param = ref 0 in
  List.iter
    (function
     | Text _ -> ()
     | Param n -> max_param := max n !max_param)
    frags;
  fprintf p "  | \"%s\"%%string, " txt;
  list_iteri
    (fun i targ -> fprintf p "_x%d :: " (i + 1))
    targs;
  fprintf p "nil =>@ ";
  fprintf p "    ";
  List.iter
    (function
     | Text s -> fprintf p "%s" s
     | Param n -> fprintf p "_x%d" n)
    frags;
  fprintf p "@ "

let print_assertions p =
  if !assertions <> [] then begin
    fprintf p "Definition assertions (txt: string) args : Prop :=@ ";
    fprintf p "  match txt, args with@ ";
    List.iter (print_assertion p) !assertions;
    fprintf p "  | _, _ => False@ ";
    fprintf p "  end.@ @ "
  end

(* The prologue *)

let prologue = "\
Require Import Clightdefs.

Local Open Scope Z_scope.

"

(* All together *)

let print_program p prog =
  fprintf p "@[<v 0>";
  fprintf p "%s" prologue;
  Hashtbl.clear temp_names;
  all_temp_names := StringSet.empty;
  define_idents p;
  List.iter (print_globdef p) prog.prog_defs;
  fprintf p "Definition composites : list composite_definition :=@ ";
  print_list print_composite_definition p prog.prog_types;
  fprintf p ".@ @ ";
  fprintf p "Definition prog : Clight.program := {|@ ";
  fprintf p "prog_defs :=@ %a;@ " (print_list print_ident_globdef) prog.prog_defs;
  fprintf p "prog_public :=@ %a;@ " (print_list ident) prog.prog_public;
  fprintf p "prog_main := %a;@ " ident prog.prog_main;
  fprintf p "prog_types := composites;@ ";
  fprintf p "prog_comp_env := make_composite_env composites;@ ";
  fprintf p "prog_comp_env_eq := refl_equal _@ ";
  fprintf p "|}.@ ";
  print_assertions p;
  fprintf p "@]@."

