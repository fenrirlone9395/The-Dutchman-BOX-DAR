#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=$(xcrun --show-sdk-path)
xcrun clang++ -std=c++20 -O3 -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/asrc_spectrum.cpp -o build/asrc_spectrum
./build/asrc_spectrum "${1:-build/src-comparison-release}"
