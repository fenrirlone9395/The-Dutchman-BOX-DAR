#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/recovery-baseline
# Compare all modes against the shipped 0.0.20, not merely an idealized SRC.
git archive 362b84fc95519c42189d9d83c310923b635bac8e src | tar -x -C build/recovery-baseline
SDK=$(xcrun --show-sdk-path)
ARGS=(-std=c++20 -O2 -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1")
xcrun clang++ "${ARGS[@]}" tests/recovery_audio_parity.cpp -o build/recovery-current
xcrun clang++ "${ARGS[@]}" '-DBRIDGE_HEADER="../build/recovery-baseline/src/AudioBridge.hpp"' tests/recovery_audio_parity.cpp -o build/recovery-baseline-probe
# Temporary raw comparison data is removed after the test; no WAV files are created.
trap 'rm -f build/recovery-current.f32 build/recovery-baseline.f32' EXIT
./build/recovery-current > build/recovery-current.f32
./build/recovery-baseline-probe > build/recovery-baseline.f32
cmp build/recovery-current.f32 build/recovery-baseline.f32
printf 'PASS: byte-identical audio to 0.0.20 in Legacy/Direct/Fixed/Async, including starvation, queue burst, gain/EQ/Spatial/mute automation (4505600 Float32 samples)\n'
