(* A version of Earley which incorporates the optimization from Leo'91 


   NOTE currently this is just a simplified and more efficient version of
   Earley; it doesn't include Leo's optimization currently
*)


open Earley_util.Set_ops
open Earley_util.Map_ops

(* FIXME probably separate out monad from NEEDED, and apply the functor to the state passing monad *)

module type MONAD = sig
  type 'a m
  val return : 'a -> 'a m
  val ( >>= ): 'a m -> ('a -> 'b m) -> 'b m
end


module Make(Monad:MONAD)(Requires: Earley_util.NEEDED_BASIC_INTERFACE) = struct
  open Monad
  open Requires
  (* maintain invariant that if (X->i,as,k,B bs) is in the current
     set, and nullable(B) then (X -> i,as B, k, bs) is in the set *)


  let earley 
      ~add_blocked_item_at_current_k   (* needs to add all transitively nullable items as well *)
      ~add_item_at_suc_k  (* after matching a terminal; ditto transitively nullable  *)
      ~cut
      ~cut_complete_item_at_curr_k_with_blocked_items_and_add_new_items
      ~expand_nonterm     (* takes k as argument *)
      ~finished 
      ~get_item
      ~get_k 
      ~have_we_expanded_nonterm_at_current_k 
      ~incr_k 
      ~input_matches_tm_at_k
      ~note_complete_item_at_current_k
      ~nt_item_ops
    = 
    let { dot_nt; dot_i; dot_bs_hd } = nt_item_ops in
    let loop_at_k = 
      get_k () >>= fun k -> 
      let process_itm itm = 
        match dot_bs_hd itm with 
        | None -> (
            (* NOTE complete item (i,X,k) *)
            let (i,_X) = (dot_i itm, dot_nt itm) in
            note_complete_item_at_current_k ~i ~nt:_X >>= fun seen_before ->
            match seen_before with
            | true -> return ()
            | false -> 
              (* cut with blocked items *)
              (* FIXME is it clear that we never twice add an item to the list ? Needs some thought here *)
              cut_complete_item_at_curr_k_with_blocked_items_and_add_new_items ~i ~nt:_X >>= fun () ->
              return ())              
        | Some _S -> 
          _S |> sym_case 
            ~nt:(fun _X ->
                add_blocked_item_at_current_k ~nt:_X ~itm >>= fun () ->
                have_we_expanded_nonterm_at_current_k ~nt:_X >>= function
                | true -> return ()
                | false -> 
                  expand_nonterm ~k ~nt:_X >>= fun () ->
                  return ())
            ~tm:(fun tm -> 
                input_matches_tm_at_k ~k ~tm |> function
                | true -> 
                  let itm' : nt_item = cut itm (k+1) in
                  add_item_at_suc_k ~itm:itm'
                | false ->
                  return ())
      in
      let rec loop () =
        get_item () >>= function
        | Some itm -> 
          process_itm itm >>= fun () -> 
          loop ()
        | None ->
          return ()
      in
      loop ()
    in
    let rec earley () =
      loop_at_k >>= fun () ->
      incr_k () >>= fun () ->        
      (* finished if no initial items at the next stage, or we have reached the end of the input *)
      finished () >>= function
      | true -> return ()  (* actually return the final state *)
      | false -> earley ()
    in
    earley

  let _ = earley


end



(* specialize monad and implement reqs ----------------------------- *)

open Tjr_monad
open Tjr_monad.Monad

open Simple_datastructure_implementations.S

module Set_nt = Set.Make(
  struct type t = nt let compare : t -> t -> int = Pervasives.compare end)
type nt_set = Set_nt.t
let nt_set_ops = Set_nt.{ add; mem; empty; is_empty; elements }

type state = {
  k:int;
  current_items: nt_item list;
  todo_done_at_k: nt_item_set;
  items_at_suc_k: nt_item_set;
  nonterms_expanded_at_current_k: nt_set;
  complete_items_at_current_k: ixk_set;
  bitms_at_k: map_nt;
  bitms_lt_k: map_nt array
}

let make_empty_state ~input_length = {
  k=0;
  current_items=[];
  todo_done_at_k=nt_item_set_ops.empty;
  items_at_suc_k=nt_item_set_ops.empty;
  nonterms_expanded_at_current_k=nt_set_ops.empty;
  complete_items_at_current_k=ixk_set_ops.empty;
  bitms_at_k=map_nt_ops.map_empty;
  bitms_lt_k=Array.make (input_length+1) map_nt_ops.map_empty
}

module M = struct
  open Tjr_monad.State_passing_instance
  type 'a m = ('a,state state_passing) Monad.m
  let mops = monad_ops()
  let return = mops.return
  let ( >>= ) = mops.bind
end


module Leo = Make(M)(Simple_datastructure_implementations.S)

let with_world = State_passing_instance.with_world

(* FIXME we probably want an option to cut an item without altering the k val *)

(* NOTE expand_nonterm must update nonterms_expanded_at_current_k;
   actually assume that the function passed in simply returns the
   ntitems *)
let make_earley ~nullable ~expand_nonterm ~input_length ~input_matches_tm_at_k = (
  let trans_items ~k itm = 
    (* Printf.printf "Called %d %d %d %d \n%!" itm.nt itm.i_ itm.k_ (List.length itm.bs); *)
    let rec f itm = 
      (* Printf.printf "f %d %d %d %d \n%!" itm.nt itm.i_ itm.k_ (List.length itm.bs); *)

      itm::(
        match dot_bs_hd itm with
        | None -> []
        | Some s ->
          match nullable s with
          | true -> f (cut itm k)
          | false -> [])
    in
    f itm
  in

  let add_many_items set itms =
    itms |> Earley_util.List_.with_each_elt
      ~init_state:set
      ~step:(fun ~state itm -> 
          nt_item_set_ops.add itm state)
  in
                     
  let add_blocked_item_at_current_k ~nt ~itm =
    with_world (fun s ->
        ((),{s with
             bitms_at_k=
               map_nt_ops.map_find nt s.bitms_at_k |> fun itms' ->
               (* Printf.printf "Size of itms': %d %d\n%!" s.k (nt_item_set_ops.elements itms' |> List.length); *)
               (* Printf.printf "Called %d %d %d %d \n%!" itm.nt itm.i_ itm.k_ (List.length itm.bs); *)
               nt_item_set_ops.add itm itms' |> fun itms'' ->               
               map_nt_ops.map_add nt itms'' s.bitms_at_k}))
  in

  let add_item_at_suc_k ~itm =
    with_world (fun s ->
        ((),{s with
             items_at_suc_k=
               match nt_item_set_ops.mem itm s.items_at_suc_k with
               | true -> s.items_at_suc_k
               | false -> 
                 (trans_items ~k:(s.k+1) itm) 
                 |> add_many_items s.items_at_suc_k}))
  in

  let cut_complete_item_at_curr_k_with_blocked_items_and_add_new_items ~i ~nt =
    with_world (fun s ->
        ((),match s.k=i with 
          | true -> s
          | false -> 
            (* i < k *)
            (* get blocked items *)
            Array.get s.bitms_lt_k i |> fun bitms ->
            map_nt_ops.map_find nt bitms |> fun bitms ->
            nt_item_set_ops.elements bitms |> fun bitms ->
            List.map (fun bitm -> cut bitm s.k) bitms |> fun bitms ->
            List.filter (fun bitm -> not (nt_item_set_ops.mem bitm s.todo_done_at_k)) bitms |> fun bitms ->
            List.map (trans_items ~k:s.k) bitms |> List.concat |> fun new_itms ->            
            let current_items = new_itms@s.current_items in
            (* Printf.printf "Length of items: %d\n%!" (List.length current_items); *)
            {s with current_items}))
  in


  let expand_nonterm ~k ~nt =
    with_world (fun s ->
        assert(k=s.k);
        assert(not (nt_set_ops.mem nt s.nonterms_expanded_at_current_k));
        ((),
         expand_nonterm ~k ~nt |> fun itms -> 
         List.map (trans_items ~k) itms |> List.concat |> fun new_itms ->
         (* we only expand new_itms once at each k, so the items can't already be in the current_items *)
         (* List.filter (fun itm -> not (nt_item_set_ops.mem itm s.todo_done_at_k)) new_itms -> fun new_itms -> *)
            {s with
             current_items=new_itms@s.current_items;
             todo_done_at_k=add_many_items s.todo_done_at_k new_itms;
             nonterms_expanded_at_current_k=nt_set_ops.add nt s.nonterms_expanded_at_current_k
            }))
  in
         

  let finished () =
    with_world (fun s ->
        (s.k = input_length || [] = s.current_items),s)
  in

  let get_item () = 
    with_world (fun s ->
        s.current_items |> function
        | [] -> None,s
        | x::current_items -> Some x, {s with current_items})
  in

  let get_k () = 
    with_world (fun s -> s.k,s)
  in

  let have_we_expanded_nonterm_at_current_k ~nt =
    with_world (fun s -> 
        nt_set_ops.mem nt s.nonterms_expanded_at_current_k, s)
  in

  let incr_k () =
    with_world (fun s -> 
        (), { k=s.k+1;
              current_items=nt_item_set_ops.elements s.items_at_suc_k;
              todo_done_at_k=s.items_at_suc_k;
              items_at_suc_k=nt_item_set_ops.empty;
              nonterms_expanded_at_current_k=nt_set_ops.empty;
              complete_items_at_current_k=ixk_set_ops.empty;
              bitms_at_k=map_nt_ops.map_empty;
              bitms_lt_k=(
                Array.set s.bitms_lt_k s.k s.bitms_at_k;
                (* NOTE arrays are mutable anyway... *)
                s.bitms_lt_k);
            })
  in

  let note_complete_item_at_current_k ~i ~nt =
    with_world (fun s -> 
        let seen_before = ixk_set_ops.mem (i,nt) s.complete_items_at_current_k in
        seen_before, { s with
                       complete_items_at_current_k=(ixk_set_ops.add (i,nt) s.complete_items_at_current_k )})
  in

  let nt_item_ops = { dot_i; dot_nt; dot_k; dot_bs_hd } in  (* FIXME dot_k *)

  Leo.earley 
      ~add_blocked_item_at_current_k
      ~add_item_at_suc_k 
      ~cut
      ~cut_complete_item_at_curr_k_with_blocked_items_and_add_new_items
      ~expand_nonterm
      ~finished 
      ~get_item
      ~get_k 
      ~have_we_expanded_nonterm_at_current_k 
      ~incr_k 
      ~input_matches_tm_at_k
      ~note_complete_item_at_current_k
      ~nt_item_ops)

let _ :
nullable:(Simple_datastructure_implementations.S.sym -> bool) ->
expand_nonterm:(k:int ->
                nt:Simple_datastructure_implementations.S.nt -> nt_item list) ->
input_length:int ->
input_matches_tm_at_k:(k:int ->
                       tm:Simple_datastructure_implementations.S.tm ->
                       bool) ->
unit -> unit M.m
= make_earley

let earley ~nullable ~expand_nonterm ~input_length ~input_matches_tm_at_k ~init_items =
  let init_state = 
    make_empty_state ~input_length |> fun s ->
    {s with current_items=init_items }  (* FIXME todo_done_at_k? *)
  in
  make_earley ~nullable ~expand_nonterm ~input_length ~input_matches_tm_at_k ()
  |> State_passing_instance.run
    ~init_state
  |> fun (a,s) -> s


let _ : 
nullable:(sym -> bool) ->
expand_nonterm:(k:int -> nt:nt -> nt_item list) ->
input_length:int ->
input_matches_tm_at_k:(k:int -> tm:tm ->bool) ->
init_items:nt_item list -> 
state
= earley



(* test ------------------------------------------------------------- *)

(* from simple_test.ml *)

(* Encode nonterminals and terminals as ints; nts are even; tms are
   odd *)

let _E = 0
let _1 = 1

let nullable sym = match sym with 
  | _ when sym=_E -> true
  | _ -> false

(* Encode the grammar E -> E E E | "1" | eps; eps is captured by nullable *)
let rhss = [ [_E;_E;_E]; [_1] ]

(* Provide a function that produces new items, given a nonterminal and
   an input position k *)
let expand_nonterm ~k ~nt = match () with
  | _ when nt = _E -> 
    rhss   (* E -> E E E | "1" | eps *)
    |> List.map (fun bs -> { nt; i_=k; k_=k; bs})
  | _ -> failwith __LOC__

(* Example input; use command line argument *)
let input = String.make (Sys.argv.(1) |> int_of_string) '1'

let input_length = String.length input

(* Provide a function that details how to parse terminals at a given
   position k in the input *)
let input_matches_tm_at_k ~k ~tm =
  assert (tm=_1);
  if k < input_length then true else false


(* Initial nonterminal *)
let init_nt = _E

let nt_item_ops = {
  dot_nt;
  dot_i;
  dot_k;
  dot_bs_hd
}



(* Finally, run Earley! *)

let main () = 
  earley ~nullable ~expand_nonterm ~input_length ~input_matches_tm_at_k
    ~init_items:[{nt=_E; i_=0; k_=0; bs=[_E]}]
  |> fun s -> s.k |> string_of_int |> print_endline

let _ = main ()

(*

$ leo $ time ./leo.native 200
200

real	0m2.546s
user	0m2.544s
sys	0m0.000s

Slower because we need to avoid adding items we have already seen?


$ leo $ time ./leo.native 400
400

real	0m34.919s
user	0m34.896s
sys	0m0.020s

v. slow compared to test/test2

*)
