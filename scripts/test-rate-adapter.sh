#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK=$(xcrun --show-sdk-path)
xcrun clang++ -std=c++20 -O1 -g -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/rate_adapter_tests.cpp -o build/rate_adapter_tests
./build/rate_adapter_tests
