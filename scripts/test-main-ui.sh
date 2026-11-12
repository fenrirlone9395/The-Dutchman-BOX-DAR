#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -fobjc-arc -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined -Wno-unused-parameter tests/main_ui_tests.mm src/Output.mm src/ProcessTap.mm src/ClockDiagnostics.mm src/MeterView.mm src/RackControls.mm src/SpatialView.mm src/Theme.mm src/plugins/AURack.mm src/plugins/AURackUI.mm -framework Cocoa -framework CoreAudioKit -framework AudioToolbox -framework CoreAudio -framework ScreenCaptureKit -framework CoreMedia -o build/main_ui_tests
./build/main_ui_tests
