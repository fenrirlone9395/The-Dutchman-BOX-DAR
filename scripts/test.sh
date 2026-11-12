#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/bridge_tests.cpp -o build/bridge_tests
./build/bridge_tests
xcrun clang++ -std=c++20 -O1 -g -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/dsp_tests.cpp -o build/dsp_tests
./build/dsp_tests
