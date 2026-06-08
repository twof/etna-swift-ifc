import Foundation
import IFC
import IFCGen
import PropertyTestingKit

// Differential oracle. Generates a corpus of variations, then emits BOTH:
//   * <out>/swift.txt — Swift's SSNI verdict for each variation under the clean
//     table and all 20 mutant tables (one 21-char T/F/D string per line), and
//   * <out>/Oracle.v  — a Coq program that reconstructs the *same* variations as
//     `ifc-basic` terms and prints the same verdict strings.
// Compiling Oracle.v against the QuickChick reference and diffing the two files
// validates the Swift machine (exec), indist, SSNI, and `mutateTable` (all 20
// mutant tables, by column) against the reference in one shot.

func verdictChar(_ o: Bool?) -> String {
    switch o {
    case .some(true): return "T"
    case .some(false): return "F"
    case .none: return "D"
    }
}

// clean + mutant[0..19], in order.
func verdictLine(_ v: Variation) -> String {
    var s = verdictChar(propSSNI(defaultTable, v))
    for m in ifcMutants { s += verdictChar(propSSNI(m, v)) }
    return s
}

func buildCorpus(_ count: Int) -> [Variation] {
    var rng = FastRNG()
    var corpus = ifcSeeds            // include the known witnesses (exercise F)
    for _ in 0..<count { corpus.append(genVariation(&rng)) }
    return corpus
}

func emitCoq(_ corpus: [Variation]) -> String {
    var terms: [String] = []
    for v in corpus { terms.append("  (\(coqVariation(v)))") }
    let corpusLit = "[\n" + terms.joined(separator: ";\n") + "\n]"
    return """
    Require Import List ZArith Coq.Strings.String.
    Import ListNotations.
    (* ifcbasic modules imported LAST so e.g. Instructions.Add shadows List.Add. *)
    From QuickChick.ifcbasic Require Import Rules Instructions Machine Indist Generation Mutate.
    Open Scope Z_scope.

    (* Boolean SSNI mirroring Driver.v's checker logic. None = rejected/discard. *)
    Definition ssniB (t : table) (v : @Variation State) : option bool :=
      let '(V st1 st2) := v in
      let '(St _ _ _ (_@l1)) := st1 in
      let '(St _ _ _ (_@l2)) := st2 in
      match lookupInstr st1 with
      | Some _ =>
        if indist st1 st2 then
          match l1, l2 with
          | L,L =>
            match exec t st1, exec t st2 with
            | Some st1', Some st2' => Some (indist st1' st2')
            | _, _ => None
            end
          | H,H =>
            match exec t st1, exec t st2 with
            | Some st1', Some st2' =>
              if is_atom_low (st_pc st1') && is_atom_low (st_pc st2') then Some (indist st1' st2')
              else if is_atom_low (st_pc st1') then Some (indist st2 st2')
              else Some (indist st1 st1')
            | _, _ => None
            end
          | H,_ =>
            match exec t st1 with Some st1' => Some (indist st1 st1') | _ => None end
          | _,H =>
            match exec t st2 with Some st2' => Some (indist st2 st2') | _ => None end
          end
        else None
      | _ => None
      end.

    Definition muts : list table := mutate_table default_table.
    Definition tableAt (n : nat) : table :=
      match nth_error muts n with Some t => t | None => default_table end.

    Definition sv (o : option bool) : string :=
      match o with Some true => "T" | Some false => "F" | None => "D" end.

    Definition vline (v : @Variation State) : string :=
      String.concat "" (map sv (ssniB default_table v :: map (fun n => ssniB (tableAt n) v) (seq 0 20))).

    Definition corpus : list (@Variation State) :=
    \(corpusLit).

    Compute (List.length muts).
    Compute (map vline corpus).
    """
}

let args = CommandLine.arguments
guard args.count >= 4, args[1] == "emit", let count = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: ifc-oracle emit <count> <outdir>\n".utf8))
    exit(2)
}
let outdir = args[3]
let corpus = buildCorpus(count)

let swiftLines = corpus.map(verdictLine).joined(separator: "\n") + "\n"
try? swiftLines.write(toFile: "\(outdir)/swift.txt", atomically: true, encoding: .utf8)
try? emitCoq(corpus).write(toFile: "\(outdir)/Oracle.v", atomically: true, encoding: .utf8)
print("emitted \(corpus.count) variations -> \(outdir)/swift.txt + \(outdir)/Oracle.v")
