#!/bin/bash
# Run the built `ifc` solve binary with the patched toolchain's runtime on the
# dylib path.
#   run-ifc.sh <strategy> <property> [duration_seconds] [mutant_index]
# strategy: "ptk"; property: "SSNI"; mutant_index selects a table from
# mutateTable (omitted = the clean default table).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"
CONFIG="${CONFIG:-debug}"
exec env DYLD_LIBRARY_PATH="$RT" "$ROOT/.build/$CONFIG/ifc" "$@"
