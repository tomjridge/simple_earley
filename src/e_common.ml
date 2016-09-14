(* ---------------------------------------- *)
(*adoc == Util *)

let dest_Some = function Some x -> x | _ -> (failwith "dest_Some")

let find_with_default d f k m = try (f k m) with Not_found -> d

let rec while_not_nil: 'a list -> 's -> ('s -> 'a -> 's) -> 's = (
    fun xs s0 f -> List.fold_left f s0 xs)


(* ---------------------------------------- *)
(*adoc == Common type definitions, all versions *)

type k_t = int
type i_t = int
type j_t = int


(*adoc Symbols *)

type nt = int
type tm = int
type sym = NT of nt | TM of tm


(*adoc Items *)


(* l:bc *)
type nt_item = {
    nt: nt;
    i: i_t;
    as_: sym list;
    k: k_t;
    bs: sym list
  }



(* l:bh *)
type tm_item = {
    k: k_t;
    tm: tm
  }


(* l:bm *)
type sym_item = {
    k: k_t;
    sym: sym
  }

(* l:cd *)
(*adoc Complete item *)
type citm_t = {
    k: k_t;
    sym: sym;
    j: j_t 
  }


(* l:de *)
type string_t
type substring_t = (string_t * i_t * j_t)

let string_to_string_t: string -> string_t = (fun s -> Obj.magic s)
let string_t_to_string: string_t -> string = (fun s -> Obj.magic s)

(* l:ef *)
type grammar_t = {
    nt_items_for_nt: nt -> (string_t * int) -> nt_item list;
    p_of_tm: tm -> substring_t -> k_t list
  }

type input_t = {
    str: string_t;
    len: int;
  }

type ctxt_t = {
    g0: grammar_t;
    i0: input_t
  }


let cut: nt_item -> j_t -> nt_item = (
    fun bitm j0 -> (
      let as_ = (List.hd bitm.bs)::bitm.as_ in
      let bs = List.tl bitm.bs in
      let k = j0 in
      let nitm ={bitm with k;as_;bs} in
      nitm ))



(* ---------------------------------------- *)
(*adoc Blocked and complete maps? FIXME *)

module Unstaged = struct

  type bitm_t = nt_item  (* bs <> [] *)

  type b_key_t = (k_t * sym)

  let bitm_to_key: bitm_t -> b_key_t = (
      fun bitm -> (bitm.k,List.hd bitm.bs))

  type c_key_t = (k_t * sym)
               
  let citm_to_key: citm_t -> c_key_t = (
      fun citm -> (citm.k,citm.sym))

end


(* ---------------------------------------- *)
(*adoc == Various sets and maps *)

let comp = Pervasives.compare

module Int_set = 
  Set.Make(struct type t = int;; let compare: t -> t -> int = comp end)

module Nt_item_set = 
  Set.Make(struct type t = nt_item;; let compare: t -> t -> int = comp end)

module Sym_item_set = 
  Set.Make(struct type t = sym_item;; let compare: t -> t -> int = comp end)

module Nt_set = 
  Set.Make(struct type t = nt;; let compare: t -> t -> int = comp end)

module Map_tm =
  Map.Make(struct type t = tm;; let compare: t -> t -> int = comp end)

module Map_nt =
  Map.Make(struct type t = nt;; let compare: t -> t -> int = comp end)

module Map_int = 
  Map.Make(struct type t = int;; let compare: t -> t -> int = comp end)



(* ---------------------------------------- *)
(*adoc == Debug support *)

let debug = ref false

let debug_endline = (
    fun x -> 
    if !debug then print_endline x else ())

let sym_to_string s = (match s with | NT nt -> Printf.sprintf "NT %d" nt | TM tm -> Printf.sprintf "TM %d" tm)

let sym_list_to_string ss = (ss |> List.map sym_to_string |> String.concat "," |> fun x -> "["^x^"]")

let nitm_to_string nitm = (
    Printf.sprintf "(%d %d %s %d %s)" 
                   nitm.nt nitm.i 
                   (sym_list_to_string nitm.as_) 
                   nitm.k 
                   (sym_list_to_string nitm.bs))

