#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -fobjc-arc -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/vst3/catalog_tests.mm -framework Foundation -o build/catalog_tests
./build/catalog_tests
