#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/vst3-sources.sh
SDK="$(xcrun --show-sdk-path)"
flags=(-isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" -std=c++20 -O1 -g -fobjc-arc -arch arm64 -mmacosx-version-min=14.0 "${VST3_FLAGS[@]}")
if [[ "${VST3_SANITIZE:-0}" == "1" ]]; then flags+=(-fsanitize=address,undefined); fi
mkdir -p build/BOXGain.vst3/Contents/MacOS
xcrun clang++ "${flags[@]}" -bundle tests/vst3/Fixture.mm "$VST3_SDK/pluginterfaces/base/funknown.cpp" "$VST3_SDK/pluginterfaces/base/coreiids.cpp" "$VST3_SDK/public.sdk/source/common/commoniids.cpp" "$VST3_SDK/public.sdk/source/vst/vstinitiids.cpp" -framework Cocoa -o build/BOXGain.vst3/Contents/MacOS/BOXGain
cat > build/BOXGain.vst3/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>BOXGain</string><key>CFBundleIdentifier</key><string>local.dutchman.tests.vst3gain</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
PLIST
xcrun clang++ "${flags[@]}" tests/vst3/host_tests.mm src/plugins/AURack.mm "${VST3_SOURCES[@]}" -framework Cocoa -framework AudioToolbox -o build/vst3_tests
./build/vst3_tests "$@"
