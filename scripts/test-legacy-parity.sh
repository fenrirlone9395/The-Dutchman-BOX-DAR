#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/parity-baseline
# The pinned comparison object is preserved in the repository, not downloaded.
git archive b6b4c4135c42f078591332845322c61d38219adc src | tar -x -C build/parity-baseline
SDK=$(xcrun --show-sdk-path)
ARGS=(-std=c++20 -O2 -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1")
xcrun clang++ "${ARGS[@]}" tests/legacy_parity.cpp -o build/parity-current
xcrun clang++ "${ARGS[@]}" '-DBRIDGE_HEADER="../build/parity-baseline/src/AudioBridge.hpp"' tests/legacy_parity.cpp -o build/parity-baseline-probe
./build/parity-current > build/parity-current.f32
./build/parity-baseline-probe > build/parity-baseline.f32
cmp build/parity-current.f32 build/parity-baseline.f32
printf 'PASS: Legacy output is byte-identical to b6b4c41 across rates, gain/EQ/Spatial/Limiter automation and mute (1536000 Float32 samples)\n'
