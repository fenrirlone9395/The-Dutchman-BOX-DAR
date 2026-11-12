#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/The Dutchman BOX-DAR.app"
mkdir -p "$APP/Contents/MacOS"
SDK="$(xcrun --show-sdk-path)"
xcrun clang++ -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -std=c++20 -O2 -Wall -Wextra -Wno-unused-parameter -fobjc-arc -arch arm64 -mmacosx-version-min=14.0 src/Main.mm src/Output.mm src/ProcessTap.mm src/MeterView.mm src/RackControls.mm src/SpatialView.mm src/Theme.mm src/plugins/AURack.mm src/plugins/AURackUI.mm -framework CoreAudioKit -framework Cocoa -framework ScreenCaptureKit -framework CoreMedia -framework AudioToolbox -framework CoreAudio -o "$APP/Contents/MacOS/DesktopAudioRack"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
