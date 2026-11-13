#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O2 -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/transparency_audit.cpp -o build/transparency_audit
./build/transparency_audit
