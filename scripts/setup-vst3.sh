#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
revision=9fad9770f2ae8542ab1a548a68c1ad1ac690abe0
if [[ ! -d build/vst3sdk/.git ]]; then
  git clone --depth 1 --branch v3.8.0_build_66 https://github.com/steinbergmedia/vst3sdk.git build/vst3sdk
fi
[[ "$(git -C build/vst3sdk rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected VST3 SDK revision' >&2; exit 1; }
git -C build/vst3sdk submodule update --init --depth 1 pluginterfaces base public.sdk
