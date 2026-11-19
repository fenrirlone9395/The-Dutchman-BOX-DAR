#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O2 -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/hrtf_tests.cpp -framework AudioToolbox -o build/hrtf_tests
./build/hrtf_tests
