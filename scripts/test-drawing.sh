#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -fobjc-arc -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/drawing_tests.mm src/MeterView.mm src/RackControls.mm src/plugins/AURack.mm -framework Cocoa -framework AudioToolbox -o build/drawing_tests
./build/drawing_tests
