#pragma once
#include "AudioBridge.hpp"
#include <CoreAudio/CoreAudio.h>
// Preserve the first stereo pair at its original sample level. Never sum/average
// unused hardware outputs into it (wide hardware streams may contain 8+ channels).
inline bool pushTapStereo(AudioBridge& bridge,const AudioBufferList* data) {
    if(!data || !data->mNumberBuffers) return false;
    const auto& first=data->mBuffers[0];
    if(first.mNumberChannels>=2 && first.mData) {
        auto* p=static_cast<const float*>(first.mData);
        const auto frames=first.mDataByteSize/(sizeof(float)*first.mNumberChannels);
        if(!frames)return false;
        bridge.push(p,p+1,frames,first.mNumberChannels);
        return true;
    }
    if(first.mNumberChannels==1 && first.mData && data->mNumberBuffers>=2) {
        const auto& second=data->mBuffers[1];
        if(second.mNumberChannels!=1 || !second.mData) return false;
        const auto frames=std::min(first.mDataByteSize,second.mDataByteSize)/sizeof(float);
        if(!frames)return false;
        bridge.push(static_cast<const float*>(first.mData),static_cast<const float*>(second.mData),frames,1);
        return true;
    }
    return false;
}
