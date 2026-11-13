#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/vst3-sources.sh
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -std=c++20 -O1 -g -fobjc-arc -arch arm64 -mmacosx-version-min=14.0 "${VST3_FLAGS[@]}" tests/vst3/rack_ui_tests.mm src/plugins/AURack.mm src/plugins/AURackUI.mm src/plugins/RackSlotView.mm src/Theme.mm "${VST3_SOURCES[@]}" -framework Cocoa -framework CoreAudioKit -framework AudioToolbox -o build/vst3_ui_tests
./build/vst3_ui_tests
