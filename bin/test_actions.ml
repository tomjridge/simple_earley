(** An experiment to test applying actions to the result of an Earley
   parse. *)

open Tjr_simple_earley
open Prelude
open Misc
open Spec_types
open Spec_common
open Test_unstaged
open Test_unstaged.Internal
       
let main () = 
  let grammar = Examples.get_grammar_by_name !Params.grammar in
  let initial_nt = grammar.initial_nt in
  let expand_nt,expand_tm = grammar_to_expand grammar in
  earley_unstaged ~expand_nt ~expand_tm ~initial_nt
  |> fun { count; items; complete_items } -> 
  Printf.printf "%d nt_items produced (%s)\n%!"
    count
    __FILE__;
  (* what we need from the parse; implement via (i,j) -> int set *)
  let find_max_j_leq (i:int) (sym,syms) (j:int) : int option = 
    complete_items (i,sym,syms) |> fun set -> 
    Int_set.find_last_opt (fun j' -> j' <= j) set 
  in
  let get_rhss ~nt = 
    assert(nt="E");
    let rhss = 
      grammar.rules 
      |> List.filter (fun (nt',rhs) -> nt'=nt) 
      |> List.map (fun (_,rhs) -> List.map Examples.string_to_sym rhs)
    in
    (* add in actions *)
    rhss |> List.map (fun rhs ->
        (rhs,fun vs -> List.fold_left (fun a b -> a+b) 0 vs))
  in
  let cut ~dont_return_j i (sym,syms) j = 
    (* assert(syms<>[]); NOTE no longer true *)
    find_max_j_leq i (sym,syms) (if dont_return_j then j-1 else j)
  in
  let apply_tm ~tm ~i ~j = 
    (* just return the length (0 or 1) of the string parsed *)
    assert(j-i = 0 || j-i=1);
    Some(j-i)
  in 
  let is_nt = function Nt x -> true | Tm x -> false in
  let dest_nt = function Nt x -> x | Tm x -> failwith "dest_nt" in
  let dest_tm = function Tm x -> x | Nt x -> failwith "dest_tm" in
  (* initial_nt already bound *)
  Actions.apply_actions 
    ~is_nt ~dest_nt ~dest_tm 
    ~get_rhss
    ~cut
    ~apply_tm
    ~nt_to_string:(fun x -> x)
    ~nt:initial_nt
    ~i:0
    ~j:(String.length !Params.input)
  |> function
  | None -> ()
  | Some i -> Printf.printf "Result was %d\n%!" i

let _ = main

let _ = 
  Params.input := String.make 10 '1';
  main ()    
  
