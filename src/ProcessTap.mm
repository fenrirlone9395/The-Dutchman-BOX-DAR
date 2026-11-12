#include "ProcessTap.hpp"
#include "TapInput.hpp"
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <unistd.h>
OSStatus ProcessTap::callback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList* data,const AudioTimeStamp* stamp,AudioBufferList*,const AudioTimeStamp*,void* ctx) {
    auto& b=static_cast<ProcessTap*>(ctx)->bridge;
    if(stamp && (stamp->mFlags & (kAudioTimeStampHostTimeValid|kAudioTimeStampSampleTimeValid))==(kAudioTimeStampHostTimeValid|kAudioTimeStampSampleTimeValid))b.captureTimestamp.publish(stamp->mSampleTime,stamp->mHostTime);
    pushTapStereo(b,data);
    return noErr;
}
OSStatus ProcessTap::start(bool beginIO) {
    stop();
    if(@available(macOS 14.2,*)) {
        pid_t pid=getpid(); AudioObjectID own=0; UInt32 size=sizeof(own);
        AudioObjectPropertyAddress a{kAudioHardwarePropertyTranslatePIDToProcessObject,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        OSStatus s=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,sizeof(pid),&pid,&size,&own);
        if(s || !own) return s?s:kAudio_ParamError; // Never capture without self-exclusion.
        // Capture the default hardware stream without stereo mixdown. Core Audio's
        // global stereo mixdown attenuates wide hardware outputs, even when only
        // channels 1/2 carry signal. Do not compensate with a guessed fixed gain.
        a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        size=sizeof(sourceDevice);
        s=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,&sourceDevice);
        if(s || !sourceDevice) {stop();return s?s:kAudio_ParamError;}
        CFStringRef uid=nullptr; size=sizeof(uid); a.mSelector=kAudioDevicePropertyDeviceUID;
        s=AudioObjectGetPropertyData(sourceDevice,&a,0,nullptr,&size,&uid);
        if(s || !uid) {stop();return s?s:kAudio_ParamError;}
        CATapDescription* description=[[CATapDescription alloc] initExcludingProcesses:@[@(own)] andDeviceUID:(__bridge NSString*)uid withStream:0];
        CFRelease(uid);
        description.mixdown=NO;
        description.privateTap=YES; description.muteBehavior=CATapMutedWhenTapped; description.name=@"The Dutchman System Audio";
        s=AudioHardwareCreateProcessTap(description,&tap); if(s) {stop();return s;}
        AudioStreamBasicDescription format{}; size=sizeof(format); a.mSelector=kAudioTapPropertyFormat;
        s=AudioObjectGetPropertyData(tap,&a,0,nullptr,&size,&format);
        if(s || format.mFormatID!=kAudioFormatLinearPCM || !(format.mFormatFlags&kAudioFormatFlagIsFloat) || format.mBitsPerChannel!=32 || format.mChannelsPerFrame<2 || format.mSampleRate<8000) { stop();return s?s:kAudioUnitErr_FormatNotSupported; }
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
        if(!s && beginIO) s=AudioDeviceStart(device,io);
        if(s) stop(); return s;
    }
    return kAudioHardwareUnsupportedOperationError;
}
OSStatus ProcessTap::resume(){return device&&io?AudioDeviceStart(device,io):kAudio_ParamError;}
bool ProcessTap::sourceIsCurrent() const {
    AudioDeviceID current=0; UInt32 size=sizeof(current);
    AudioObjectPropertyAddress a{kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    return sourceDevice && !AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,nullptr,&size,&current) && current==sourceDevice;
}
void ProcessTap::stop() {
    if(device && io) { AudioDeviceStop(device,io); AudioDeviceDestroyIOProcID(device,io); io=nullptr; }
    if(device) {AudioHardwareDestroyAggregateDevice(device);device=0;}
    if(@available(macOS 14.2,*)) {if(tap) {AudioHardwareDestroyProcessTap(tap);tap=0;}}
    sourceDevice=0;
}
