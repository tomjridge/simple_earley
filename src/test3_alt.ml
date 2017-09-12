(* test3_alt: represent nt_item as int *)

open Staged3
open Set_ops
open Map_ops


module Map_make = functor (Ord:Set.OrderedType) -> struct
  include struct
    module X = Map.Make(Ord)
    open X
    type 'a t = 'a X.t
    let map_add = add
    let map_find default = fun k m ->
      try find k m with _ -> default
    let map_empty = empty
    let map_remove = remove
  end
end


module S = struct
  type i_t = int
  type k_t = int
  type j_t = int
  type nt = int (* even, say *)
  type tm = int (* odd, say *)
  type sym = int
  let even x = (x mod 2 = 0)
  let sym_case ~nt ~tm sym = 
    if even sym then nt sym else tm sym

  let _NT: nt -> sym = fun x -> x

  (* here we have a bound on sym which we can use for encoding a list;
     we also have a bound on max length of list; alternatively just
     number the possible rhs?

     from an nt_item, we want to extract nt,i,k, and bs; easiest to
     repn all possible bs by an int, and a lookup table to compute the
     relevant sym list
     
     we also need to be able to take the tl of a list of bs
  *)
  
  let rec tails = function
    | [] -> [[]]
    | _::xs' as xs -> xs::tails xs'

  type rhs = sym list

  (* xs are right-hand sides; every suffix must be numbered *)
  let mk_table xs : rhs array =
    let count = ref 0 in
    let arr = Array.make 100 [] in  (* array of sym_list *)  (* FIXME 100 *)
    List.iter 
      (fun x ->
         (* x is a rhs, so take all suffixes *)
         tails x |> List.iter (fun suff -> arr.(!count) <- suff; count:=!count+1))
      xs
    ;
    Printf.printf "%d\n" !count;
    arr

  let _ = mk_table

  (* scan array entries till property holds; return arr index; FIXME move to tjr_lib *)
  let scan arr p = 
    let rec f n = 
      if n >= Array.length arr then None else
        if p (arr.(n)) then Some n else f (n+1)
    in
    f 0

  let lookup arr rhs =
    scan arr (fun x -> x=rhs)

  (*
  let _arr = mk_table [[1;1;1]]

  let _tmp = lookup _arr [1]
  *)

  (* nt,i,k,bs - repn as int, nt*b^3 + i*b^2 + k*b^1 + bs? *)
  type nt_item = int


  let b1 = 1024 
  let b2 = b1 * 1024 
  let b3 = b2 * 1024 

  let to_int (nt,i,k,bs) = 
    nt*b3 + i*b2 + k*b1 + bs

  let mk_nt_item arr nt i k bs =
    let bs' = lookup arr bs|>function Some x -> x | _ -> failwith __LOC__ in
    assert(bs'<b1);      (* assume lookup ... < 1024 *)
    to_int (nt,i,k,bs')

  let dot_nt nitm = nitm / b3
  let dot_i nitm = (nitm / b2) mod b1
  let dot_k nitm = (nitm / b1) mod b1
  let dot_bs_as_int nitm = nitm mod b1
  let dot_bs' (arr:sym list array) nitm = dot_bs_as_int nitm |> fun x -> arr.(x)  (* notice that we need the array to get the actual list *)

  (* FIXME do we want to pass an aux data around for dot_bs and cut? no, better to pass operations at runtime *)

(*
  let _nitm = mk_nt_item _arr 3 4 5 [1]

  let _nt = _nitm |> dot_nt
  let _i,_k,_bs = (_nitm|>dot_i),(_nitm|>dot_k),(_nitm|>dot_bs' _arr)
*)

  (* NOTE following doesn't actually depend on arr *)
  let cut : nt_item -> j_t -> nt_item = 
    let from_int nitm = (dot_nt nitm,dot_i nitm, dot_k nitm, dot_bs_as_int nitm) in
    fun bitm j0 -> 
      (*        let as_ = (List.hd bitm.bs)::bitm.as_ in*)
      let (nt,i,k,bs) = from_int bitm in
      let bs = bs+1 in (* NOTE artefact of the numbering *)
      let k = j0 in
      let nitm =to_int (nt,i,k,bs) in
      nitm 
  type cut = nt_item -> j_t -> nt_item


  type nt_item_ops = {
    dot_nt: nt_item -> nt;
    dot_i: nt_item -> i_t;
    dot_k: nt_item -> k_t;
    dot_bs: nt_item -> sym list;
  }

                      
  module Set_nt_item = Set.Make(
    struct type t = nt_item let compare : t -> t -> int = Pervasives.compare end)
  type nt_item_set = Set_nt_item.t
  let nt_item_set_ops = Set_nt_item.{ add;mem;empty;is_empty;elements }
  let nt_item_set_with_each_elt ~f ~init_state set =
    Set_nt_item.fold (fun e acc -> f ~state:acc e) set init_state

  type ixk=(i_t*nt)
  module Set_ixk = Set.Make(
    struct type t = ixk let compare : t -> t -> int = Pervasives.compare end)
  type ixk_set = Set_ixk.t
  let ixk_set_ops = Set_ixk.{ add;mem;empty;is_empty;elements } 
  
  module Map_nt = Map_make(
      struct type t = nt let compare : t -> t -> int = Pervasives.compare end)
  type map_nt = nt_item_set Map_nt.t
  let map_nt_ops = Map_nt.{ map_add;map_find=map_find nt_item_set_ops.empty;map_empty;map_remove }

  module Map_int = Map_make(
      struct type t = int let compare : t -> t -> int = Pervasives.compare end)
  type map_int = nt_item_set Map_int.t
  let map_int_ops = 
    Map_int.{ map_add;map_find=map_find nt_item_set_ops.empty;map_empty;map_remove }

  module Map_tm = Map_make(
      struct type t = tm let compare : t -> t -> int = Pervasives.compare end)
  type map_tm = int list option Map_tm.t
  let map_tm_ops = Map_tm.{ map_add;map_find=map_find None;map_empty;map_remove }

  type bitms_lt_k = (*nt_item_set*) map_nt array
  type bitms_lt_k_ops = (int,map_nt,bitms_lt_k) map_ops

  type todo_gt_k = map_int
  let todo_gt_k_ops = map_int_ops

  let debug_enabled = false
  let debug_endline (s:string) = ()

end

module Staged = Staged3.Make(S)
open Staged


(* simple test ------------------------------------------------------ *)

open S

let _E = 0
let eps = 1
let _1 = 3

let rhss = [ [_E;_E;_E]; [_1]; [eps] ]

let arr : int list array = S.mk_table rhss

(* let rhss = rhss |> List.map @@ S.lookup arr *)

let new_items ~nt ~input ~k = match () with
  | _ when nt = _E -> 
    rhss   (* E -> E E E | "1" | eps *)
    |> List.map (fun bs -> let i = k in S.mk_nt_item arr nt i k bs)
  | _ -> failwith __LOC__

let input = String.make (Sys.argv.(1) |> int_of_string) '1'

let parse_tm ~tm ~input ~k ~input_length = 
  match () with
  | _ when tm = eps -> [k]
  | _ when tm = _1 -> 
    (* print_endline (string_of_int k); *)
    if String.get input k = '1' then [k+1] else []
  | _ -> failwith __LOC__

let input_length = String.length input

let init_nt = _E

let dot_bs = dot_bs' arr

let nt_item_ops = {
  dot_nt;
  dot_i;
  dot_k;
  dot_bs
}

let bitms_lt_k_ops = {
  map_add=(fun k v t -> t.(k) <- v; t);
  map_find=(fun k t -> t.(k));
  map_empty=(Array.make (input_length + 1) map_nt_ops.map_empty);   (* FIXME +1? *)
  map_remove=(fun k t -> failwith __LOC__);  (* not used *)
}

let cut = S.cut

let main () = 
  run_earley ~nt_item_ops ~bitms_lt_k_ops ~cut ~new_items ~input ~parse_tm ~input_length ~init_nt 
  |> fun s -> s.k |> string_of_int |> print_endline

let _ = main ()

(* FIXME check this is actually giving the right results 

$ src $ time ./test3.native 400
400

real	0m7.593s
user	0m7.556s
sys	0m0.032s


2017-09-12 with ints

$ src $ time ./test3_alt.native 200
8
200

real	0m0.444s
user	0m0.436s
sys	0m0.004s


$ src $ time ./test3_alt.native 400
8
400

real	0m3.670s
user	0m3.556s
sys	0m0.008s


*)