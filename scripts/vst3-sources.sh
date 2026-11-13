# Sourced by build/test scripts after changing to the BOX directory.
VST3_SDK="build/vst3sdk"
if [[ ! -f "$VST3_SDK/pluginterfaces/vst/ivstaudioprocessor.h" ]]; then
  echo 'VST3 SDK missing. Run bash scripts/setup-vst3.sh first.' >&2
  exit 1
fi
VST3_FLAGS=(-DDAR_ENABLE_VST3=1 -DRELEASE=1 -I"$VST3_SDK")
VST3_SOURCES=(src/plugins/VST3Host.mm
 "$VST3_SDK/pluginterfaces/base/funknown.cpp"
 "$VST3_SDK/pluginterfaces/base/coreiids.cpp"
 "$VST3_SDK/public.sdk/source/common/commoniids.cpp"
 "$VST3_SDK/public.sdk/source/common/memorystream.cpp"
 "$VST3_SDK/public.sdk/source/common/commonstringconvert.cpp"
 "$VST3_SDK/public.sdk/source/vst/vstinitiids.cpp"
 "$VST3_SDK/public.sdk/source/common/threadchecker_mac.mm"
 "$VST3_SDK/public.sdk/source/vst/hosting/connectionproxy.cpp"
 "$VST3_SDK/public.sdk/source/vst/hosting/hostclasses.cpp"
 "$VST3_SDK/public.sdk/source/vst/hosting/pluginterfacesupport.cpp"
 "$VST3_SDK/public.sdk/source/vst/utility/stringconvert.cpp")
