(* SSNI Checker + per-mutant properties, copied from the reference Driver.v so
   we can benchmark without importing Driver (whose top-level commands would run
   the full QuickCheck/MutateCheck suite on import). gen_variation_state is the
   bespoke generator; gen_variation_state_derived is the derived one. *)
From QuickChick Require Import QuickChick.
Require Import List. Import ListNotations.
From QuickChick.ifcbasic Require Import Machine Printing Generation Indist DerivedGen Mutate.
Require Import Coq.Strings.String. Local Open Scope string.

Definition SSNI (t : table) (v : @Variation State) : Checker :=
  let '(V st1 st2) := v in
  let '(St _ _ _ (_@l1)) := st1 in
  let '(St _ _ _ (_@l2)) := st2 in
  match lookupInstr st1 with
  | Some i => collect (show i) (
      if indist st1 st2 then
        match l1, l2 with
        | L,L =>
          match exec t st1, exec t st2 with
          | Some st1', Some st2' => checker (indist st1' st2')
          | _, _ => checker rejected
          end
        | H,H =>
          match exec t st1, exec t st2 with
          | Some st1', Some st2' =>
            if is_atom_low (st_pc st1') && is_atom_low (st_pc st2') then checker (indist st1' st2')
            else if is_atom_low (st_pc st1') then checker (indist st2 st2')
            else checker (indist st1 st1')
          | _, _ => checker rejected
          end
        | H,_ =>
          match exec t st1 with Some st1' => checker (indist st1 st1') | _ => checker rejected end
        | _,H =>
          match exec t st2 with Some st2' => checker (indist st2 st2') | _ => checker rejected end
        end
      else checker rejected)
  | _ => checker rejected
  end.

Definition prop_SSNI (t : table) : Checker :=
  forAllShrink gen_variation_state (fun _ => nil) (SSNI t : Variation -> G QProp).

Definition prop_SSNI_derived (t : table) : Checker :=
  forAllShrink gen_variation_state_derived (fun _ => nil)
    (fun mv => match mv with Some v => SSNI t v | _ => checker tt end).

Definition muts : list table := mutate_table default_table.
Definition tableAt (n : nat) : table :=
  match nth_error muts n with Some t => t | None => default_table end.
