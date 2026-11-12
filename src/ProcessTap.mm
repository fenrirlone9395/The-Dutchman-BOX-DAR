#include "ProcessTap.hpp"
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <unistd.h>
OSStatus ProcessTap::callback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList* data,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void* ctx) {
    auto& b=static_cast<ProcessTap*>(ctx)->bridge;
    if(data->mNumberBuffers==1 && data->mBuffers[0].mNumberChannels==2 && data->mBuffers[0].mData) {
        auto* p=static_cast<float*>(data->mBuffers[0].mData); b.push(p,p+1,data->mBuffers[0].mDataByteSize/8,2);
    } else if(data->mNumberBuffers==2 && data->mBuffers[0].mData && data->mBuffers[1].mData) {
        b.push(static_cast<float*>(data->mBuffers[0].mData),static_cast<float*>(data->mBuffers[1].mData),std::min(data->mBuffers[0].mDataByteSize,data->mBuffers[1].mDataByteSize)/4,1);
    }
    return noErr;
}
OSStatus ProcessTap::start() {
    stop();
    if(@available(macOS 14.2,*)) {
        pid_t pid=getpid(); AudioObjectID own=0; UInt32 size=sizeof(own);
        AudioObjectPropertyAddress a{kAudioHardwarePropertyTranslatePIDToProcessObject,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        OSStatus s=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,sizeof(pid),&pid,&size,&own);
        if(s || !own) return s?s:kAudio_ParamError; // Never capture without self-exclusion.
        CATapDescription* description=[[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[@(own)]];
        description.privateTap=YES; description.muteBehavior=CATapMutedWhenTapped; description.name=@"The Dutchman System Audio";
        s=AudioHardwareCreateProcessTap(description,&tap); if(s) {stop();return s;}
        AudioStreamBasicDescription format{}; size=sizeof(format); a.mSelector=kAudioTapPropertyFormat;
        s=AudioObjectGetPropertyData(tap,&a,0,nullptr,&size,&format);
        if(s || format.mFormatID!=kAudioFormatLinearPCM || !(format.mFormatFlags&kAudioFormatFlagIsFloat) || format.mBitsPerChannel!=32 || format.mChannelsPerFrame!=2 || format.mSampleRate<8000) { stop();return s?s:kAudioUnitErr_FormatNotSupported; }
        bridge.captureRate=format.mSampleRate;
        NSDictionary* config=@{@kAudioAggregateDeviceNameKey:@"The Dutchman Capture",@kAudioAggregateDeviceUIDKey:NSUUID.UUID.UUIDString,@kAudioAggregateDeviceIsPrivateKey:@YES,@kAudioAggregateDeviceTapAutoStartKey:@YES,@kAudioAggregateDeviceTapListKey:@[@{@kAudioSubTapUIDKey:description.UUID.UUIDString,@kAudioSubTapDriftCompensationKey:@YES}]};
        s=AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config,&device);
        if(!s) {
            Float64 rate=0; UInt32 bytes=sizeof(rate);
            AudioObjectPropertyAddress rateAddress{kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
            s=AudioObjectGetPropertyData(device,&rateAddress,0,nullptr,&bytes,&rate);
            if(!s && rate>=8000) bridge.captureRate=rate; else if(!s) s=kAudio_ParamError;
        }
        if(!s) s=AudioDeviceCreateIOProcID(device,callback,this,&io);
        if(!s) s=AudioDeviceStart(device,io);
        if(s) stop(); return s;
    }
    return kAudioHardwareUnsupportedOperationError;
}
void ProcessTap::stop() {
    if(device && io) { AudioDeviceStop(device,io); AudioDeviceDestroyIOProcID(device,io); io=nullptr; }
    if(device) {AudioHardwareDestroyAggregateDevice(device);device=0;}
    if(@available(macOS 14.2,*)) {if(tap) {AudioHardwareDestroyProcessTap(tap);tap=0;}}
}
