#pragma once
#include "AudioBridge.hpp"
#include <CoreAudio/CoreAudio.h>
// Preserve the first stereo pair at its original sample level. Never sum/average
// unused hardware outputs into it (wide AudioFuse streams may contain 8+ channels).
inline bool pushTapStereo(AudioBridge& bridge,const AudioBufferList* data) {
    if(!data || !data->mNumberBuffers) return false;
    const auto& first=data->mBuffers[0];
    if(first.mNumberChannels>=2 && first.mData) {
        auto* p=static_cast<const float*>(first.mData);
        bridge.push(p,p+1,first.mDataByteSize/(sizeof(float)*first.mNumberChannels),first.mNumberChannels);
        return true;
    }
    if(first.mNumberChannels==1 && first.mData && data->mNumberBuffers>=2) {
        const auto& second=data->mBuffers[1];
        if(second.mNumberChannels!=1 || !second.mData) return false;
        bridge.push(static_cast<const float*>(first.mData),static_cast<const float*>(second.mData),
                    std::min(first.mDataByteSize,second.mDataByteSize)/sizeof(float),1);
        return true;
    }
    return false;
}
