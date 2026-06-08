#!/bin/bash
# IFC cross-engine benchmark over the 20 generated mutant tables.
#
#  * swift/ptk           — coverage-guided fuzzer (single engine, so executions
#                          are single-threaded and comparable to QuickChick)
#  * quickchick/bespoke  — QuickChick + handwritten gen_variation_state
#  * quickchick/derived  — QuickChick + derived gen_variation_state_derived
#
# Metric: executions-to-find = tests + discards (counted the same way for both
# engines — each is the number of generated variations the engine ran before
# the counterexample). Also wall-clock time-to-find. TRIALS runs per cell; every
# trial is recorded (mutant<TAB>trial<TAB>execs<TAB>seconds[<TAB>status]).
# Output: bench/results/{ptk,qc-bespoke,qc-derived}.tsv
set -e
cd "$(dirname "$0")"
mkdir -p results
ROOT=".."
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"
PTK="$ROOT/.build/debug/ifc"
DUR="${DUR:-30}"
TRIALS="${TRIALS:-5}"

# ---- swift / ptk (single engine) ----
echo "== swift/ptk (20 mutants x $TRIALS trials, single engine, ${DUR}s cap) =="
: > results/ptk.tsv
for t in $(seq 1 "$TRIALS"); do
  for n in $(seq 0 19); do
    out=$(env DYLD_LIBRARY_PATH="$RT" IFC_PARALLELISM=1 "$PTK" ptk SSNI "$DUR" "$n")
    tests=$(printf '%s' "$out" | sed -E 's/.*"tests":([0-9]+).*/\1/')
    disc=$(printf '%s' "$out" | sed -E 's/.*"discards":([0-9]+).*/\1/')
    ns=$(printf '%s' "$out" | sed -E 's/.*"time":"([0-9]+)ns".*/\1/')
    status=$(printf '%s' "$out" | sed -E 's/.*"status":"([a-z]+)".*/\1/')
    execs=$((tests + disc))
    secs=$(echo "scale=6; $ns/1000000000" | bc)
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$t" "$execs" "$secs" "$status" >> results/ptk.tsv
  done
  echo "  trial $t done"
done

# ---- quickchick (bespoke + derived) ----
echo "== quickchick: compiling reference + SSNIb =="
export PATH=/opt/homebrew/bin:$PATH
eval "$(opam env --switch=etna-coq)"
Q="-Q . QuickChick.ifcbasic"
for f in Rules Instructions Machine Indist Generation Mutate Printing DerivedGen GenExec SSNIb; do
  coqc $Q "$f.v" >/dev/null 2>&1
done
{
  echo 'From QuickChick Require Import QuickChick.'
  echo 'From QuickChick.ifcbasic Require Import Machine SSNIb.'
  echo 'Extract Constant defNumTests => "200000".'
  for n in $(seq 0 19); do echo "QuickChick (prop_SSNI (tableAt $n))."; done
  for n in $(seq 0 19); do echo "QuickChick (prop_SSNI_derived (tableAt $n))."; done
} > Bench.v

: > results/qc-bespoke.tsv; : > results/qc-derived.tsv
for t in $(seq 1 "$TRIALS"); do
  echo "== quickchick trial $t =="
  coqc $Q Bench.v > bench-raw.txt 2>&1 || true
  # tests and discards in matching order; execs = tests + discards.
  grep -oE 'Failed after [0-9]+ tests and [0-9]+ shrinks. \([0-9]+ discards\)' bench-raw.txt \
    | sed -E 's/Failed after ([0-9]+) tests.*\(([0-9]+) discards\)/\1 \2/' > /tmp/ifc-qc-td.txt
  grep -oE 'Time Elapsed: [0-9.]+s' bench-raw.txt | grep -oE '[0-9.]+' > /tmp/ifc-qc-time.txt
  paste /tmp/ifc-qc-td.txt /tmp/ifc-qc-time.txt > /tmp/ifc-qc-all.tsv
  i=0
  while read -r tests disc secs; do
    execs=$((tests + disc))
    if [ "$i" -lt 20 ]; then n=$i; f=results/qc-bespoke.tsv; else n=$((i-20)); f=results/qc-derived.tsv; fi
    printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$execs" "$secs" >> "$f"
    i=$((i+1))
  done < /tmp/ifc-qc-all.tsv
done

echo "== rows: ptk=$(wc -l < results/ptk.tsv) qc-bespoke=$(wc -l < results/qc-bespoke.tsv) qc-derived=$(wc -l < results/qc-derived.tsv) =="
