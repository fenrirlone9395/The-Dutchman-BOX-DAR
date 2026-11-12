#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK=$(xcrun --show-sdk-path)
xcrun clang++ -std=c++20 -O3 -DNDEBUG -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/src_compare.mm -framework AudioToolbox -o build/src_compare
./build/src_compare "${1:-build/src-comparison}"
