#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -fobjc-arc -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/tap_input_tests.mm -framework Foundation -framework CoreAudio -o build/tap_input_tests
./build/tap_input_tests
