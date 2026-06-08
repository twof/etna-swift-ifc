#!/bin/bash
# Print N generated variations (wire form), one per line.  run-sampler.sh [count]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/Users/fnord/Documents/OpenSourceDev/build/Ninja-RelWithDebInfoAssert}"
RT="$BUILD_ROOT/swift-macosx-arm64/lib/swift/macosx"
CONFIG="${CONFIG:-debug}"
exec env DYLD_LIBRARY_PATH="$RT" "$ROOT/.build/$CONFIG/ifc-sampler" "$@"
