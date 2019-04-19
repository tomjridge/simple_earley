(** Simple test of Earley functionality. Set environment variable
   record_cuts in order to record info about the number of cuts (this
   doubles the run time). *)

open Tjr_simple_earley
open Tjr_simple_earley.Prelude

(* simple test ------------------------------------------------------ *)

module Base_types = struct
  type nt = E
  type tm = Eps | One
  type sym = Nt of nt | Tm of tm
  type nt_item = { nt:nt; i_:int; k_:int; bs:sym list }
end

open Base_types

(* Encode the grammar E -> E E E | "1" | eps *)
let rhss = [ [Nt E;Nt E;Nt E]; [Tm One]; [Tm Eps] ]

(* Provide a function that produces new items, given a nonterminal and
   an input position k *)
let new_items ~nt ~input ~pos:k = match nt with
  | E -> rhss 
    |> List.map (fun bs -> { nt; i_=k; k_=k; bs})

(* Example input; use command line argument *)
let input = String.make (Sys.argv.(1) |> int_of_string) '1'

(* Provide a function that details how to parse terminals at a given
   position k in the input *)
let parse_tm ~tm ~input ~pos:k ~input_length = 
  match tm with
  | Eps -> [k]
  | One ->
    (* print_endline (string_of_int k); *)
    if String.get input k = '1' then [k+1] else []

let input_length = String.length input

(* Initial nonterminal *)
let initial_nt = E

let grammar_etc = { new_items; parse_tm; input; input_length }


(* record cuts ------------------------------------------------------ *)

(* disable the following to improve timings by about 20% *)
let record_cuts =
  Sys.getenv_opt "record_cuts" |> function
  | None -> (
      Printf.printf "%s: NOTE not recording cuts\n%!" __FILE__;
      fun cs cuts -> cuts)
  | Some _ -> (fun cs cuts -> cs::cuts)

let count_cuts cuts =
  (0,cuts)
  |> Misc.iter_opt (function
      | (_,[]) -> None
      | (n,cs::cuts) -> Some(n+List.length cs,cuts))
  |> fun (n,[]) -> n


(* timing ----------------------------------------------------------- *)

let now =
  Core.(fun () ->
      Time_stamp_counter.(now () |> to_int63)
      |>Int63.to_int_exn)

let profiler = Tjr_profile.make_string_profiler ~now

let _ = Earley_base._mark_ref := profiler.mark
  

(* Finally, run Earley! *)

module Internal = Earley_simple.Make(Base_types)
open Internal

let main () = 
  run_earley_parser
    ~grammar_etc
    ~record_cuts
    ~initial_nt
  |> fun cuts -> 
  Printf.printf "Finished with %d cuts\n%!" (count_cuts cuts);
  profiler.print_summary ()

let _ = main ()


(*

2019-04-17:

make -k run_tests 
time dune exec  bin/simple_test.exe 400 # should take about 6s?
Finished

real	0m6.273s
user	0m6.253s
sys	0m0.020s

*)