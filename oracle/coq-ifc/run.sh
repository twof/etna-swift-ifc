#!/bin/bash
# Differential oracle for the IFC workload.
#
# 1. The Swift `ifc-oracle` emits a corpus of variations as BOTH its own SSNI
#    verdicts (swift.txt) and a Coq program (ifcbasic/Oracle.v) that reconstructs
#    the same variations and prints the same verdicts.
# 2. We compile the QuickChick reference machine + Oracle.v with coqc and capture
#    the `Compute (map vline corpus)` output.
# 3. We parse the Coq verdict strings and diff them against swift.txt.
#
# A clean run = the Swift machine (exec), indist, SSNI, and all 20 mutant tables
# agree with the reference on every variation (every column of every line).
#
#   ./run.sh [N]      # N random variations on top of the seed witnesses (default 400)
set -e
export PATH=/opt/homebrew/bin:$PATH
eval "$(opam env --switch=etna-coq)"
cd "$(dirname "$0")"

N="${1:-400}"
ROOT="../.."
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"

echo "== emitting corpus (N=$N) =="
env DYLD_LIBRARY_PATH="$RT" "$ROOT/.build/debug/ifc-oracle" emit "$N" "$PWD/ifcbasic"

echo "== compiling reference machine + Oracle.v =="
Q="-Q ifcbasic QuickChick.ifcbasic"
for f in Rules Instructions Machine Indist Generation Mutate; do
  coqc $Q "ifcbasic/$f.v" >/dev/null
done
# Oracle.v's `Compute` prints the verdict list to stdout.
coqc $Q "ifcbasic/Oracle.v" > coq-raw.txt 2>coq-err.txt || { cat coq-err.txt; exit 1; }

echo "== parsing + diffing =="
# Extract the quoted T/F/D verdict strings (one per variation), in order.
grep -oE '"[TFD]+"' coq-raw.txt | tr -d '"' > coq.txt
SW=$(wc -l < ifcbasic/swift.txt | tr -d ' ')
CQ=$(wc -l < coq.txt | tr -d ' ')
echo "swift lines: $SW   coq lines: $CQ   (mutant count line: $(grep -oE '= [0-9]+' coq-raw.txt | head -1))"

if [ "$SW" != "$CQ" ]; then
  echo "MISMATCH: line counts differ ($SW vs $CQ)"; exit 1
fi
if diff -q ifcbasic/swift.txt coq.txt >/dev/null; then
  echo "OK: $SW variations, all 21 verdict columns (clean + 20 mutants) identical Swift vs Coq"
else
  echo "MISMATCH on these lines:"; diff ifcbasic/swift.txt coq.txt | head -40; exit 1
fi
