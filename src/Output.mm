#include "Output.hpp"
#import <Foundation/Foundation.h>
std::vector<OutputDevice> outputDevices() {
    AudioObjectPropertyAddress a{kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=0; std::vector<OutputDevice> result;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,nullptr,&size)) return result;
    std::vector<AudioDeviceID> ids(size/sizeof(AudioDeviceID));
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,ids.data())) return result;
    for(auto id:ids) {
        a={kAudioDevicePropertyStreamConfiguration,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
        if(AudioObjectGetPropertyDataSize(id,&a,0,nullptr,&size)) continue;
        std::vector<unsigned char> data(size);
        if(AudioObjectGetPropertyData(id,&a,0,nullptr,&size,data.data())) continue;
        auto* list=reinterpret_cast<AudioBufferList*>(data.data()); UInt32 channels=0;
        for(UInt32 i=0;i<list->mNumberBuffers;i++) channels+=list->mBuffers[i].mNumberChannels;
        if(channels<2) continue;
        a={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        CFStringRef name=nullptr; size=sizeof(name);
        if(!AudioObjectGetPropertyData(id,&a,0,nullptr,&size,&name) && name) {
            result.push_back({id,[(__bridge NSString*)name UTF8String]}); CFRelease(name);
        }
    }
    return result;
}
OSStatus Output::callback(void* ctx,AudioUnitRenderActionFlags*,const AudioTimeStamp* stamp,UInt32,UInt32 frames,AudioBufferList* data) {
    auto* self=static_cast<Output*>(ctx);
    uint64_t begin=mach_absolute_time();
    self->bridge.outputActivity.observe(begin,frames,self->rate,stamp&&(stamp->mFlags&kAudioTimeStampSampleTimeValid)?stamp->mSampleTime:std::numeric_limits<double>::quiet_NaN());
    if(stamp && (stamp->mFlags & (kAudioTimeStampHostTimeValid|kAudioTimeStampSampleTimeValid))==(kAudioTimeStampHostTimeValid|kAudioTimeStampSampleTimeValid))self->bridge.outputTimestamp.publish(stamp->mSampleTime,stamp->mHostTime);
    for(UInt32 i=0;i<data->mNumberBuffers;++i) if(data->mBuffers[i].mData) memset(data->mBuffers[i].mData,0,data->mBuffers[i].mDataByteSize);
    if(data->mNumberBuffers>=2 && data->mBuffers[0].mDataByteSize>=frames*sizeof(float) && data->mBuffers[1].mDataByteSize>=frames*sizeof(float))
        self->bridge.render(static_cast<float*>(data->mBuffers[0].mData),static_cast<float*>(data->mBuffers[1].mData),frames,self->rate);
    uint64_t elapsed=mach_absolute_time()-begin;
    self->bridge.callbackTiming.record(elapsed);self->bridge.lastRenderNS=uint64_t(elapsed*self->bridge.callbackTiming.nanosPerTick);
    return noErr;
}
OSStatus Output::start(AudioDeviceID device) {
    stop();
    AudioObjectPropertyAddress a{kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=sizeof(rate); OSStatus s=AudioObjectGetPropertyData(device,&a,0,nullptr,&size,&rate);
    if(s) return s; if(rate<8000 || rate>192000) return kAudio_ParamError;
    a.mSelector=kAudioDevicePropertyBufferFrameSize; size=sizeof(bufferFrames);
    s=AudioObjectGetPropertyData(device,&a,0,nullptr,&size,&bufferFrames); if(s) return s;
    if(bridge.rack) { s=bridge.rack->prepare(rate); if(s) return s; }
    AudioComponentDescription d{kAudioUnitType_Output,kAudioUnitSubType_HALOutput,kAudioUnitManufacturer_Apple,0,0};
    auto component=AudioComponentFindNext(nullptr,&d); if(!component) return kAudio_ParamError;
    s=AudioComponentInstanceNew(component,&unit); if(s) return s;
    auto check=[&](OSStatus code){ if(code) stop(); return code; };
    UInt32 one=1,zero=0;
    if((s=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Output,0,&one,sizeof(one)))) return check(s);
    if((s=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&zero,sizeof(zero)))) return check(s);
    if((s=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&device,sizeof(device)))) return check(s);
    AudioStreamBasicDescription f{rate,kAudioFormatLinearPCM,AudioFormatFlags(kAudioFormatFlagsNativeFloatPacked)|AudioFormatFlags(kAudioFormatFlagIsNonInterleaved),4,1,4,2,32,0};
    if((s=AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&f,sizeof(f)))) return check(s);
    AURenderCallbackStruct cb{callback,this};
    if((s=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,sizeof(cb)))) return check(s);
    if((s=AudioUnitInitialize(unit))) return check(s);
    bridge.callbackTiming.prepare();bridge.captureActivity.prepare();bridge.outputActivity.prepare();
    return noErr; // Construct/initialize only; caller prepares the rate adapter before resume().
}
void Output::stop() { if(unit) { AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit); unit=nullptr; } }

void Output::pause() { if(unit) AudioOutputUnitStop(unit); }
OSStatus Output::resume() { bridge.lastPlannedResume=mach_absolute_time();bridge.fadeIn(); return unit?AudioOutputUnitStart(unit):kAudio_ParamError; }
