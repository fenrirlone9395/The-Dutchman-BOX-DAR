#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK=$(xcrun --show-sdk-path)
xcrun clang++ -std=c++20 -O1 -g -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/recovery_diagnostics_tests.cpp -o build/recovery_diagnostics_tests
./build/recovery_diagnostics_tests
