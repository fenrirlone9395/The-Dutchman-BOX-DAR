#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++20 -O1 -g -fobjc-arc -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -fsanitize=address,undefined tests/effect_menu_tests.mm src/plugins/AURack.mm src/plugins/AURackUI.mm src/Theme.mm -framework Cocoa -framework CoreAudioKit -framework AudioToolbox -o build/effect_menu_tests
./build/effect_menu_tests
