#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK=$(xcrun --show-sdk-path)
xcrun clang++ -std=c++20 -O3 -DNDEBUG -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/rate_benchmark.cpp -o build/rate_benchmark
mkdir -p build/parity-baseline
git archive b6b4c4135c42f078591332845322c61d38219adc src | tar -x -C build/parity-baseline
xcrun clang++ -std=c++20 -O3 -DNDEBUG -DUSE_BASELINE -isysroot "$SDK" -isystem "$SDK/usr/include/c++/v1" tests/rate_benchmark.cpp -o build/rate_benchmark_baseline
printf 'mode,capture_rate,output_rate,blocks,mean_us,max_us,p95_us,p99_us,p999_us,underruns,overruns\n'
./build/rate_benchmark_baseline "${1:-10000}"
./build/rate_benchmark "${1:-10000}"
