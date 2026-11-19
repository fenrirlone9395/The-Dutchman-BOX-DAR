#pragma once
#include "AudioBridge.hpp"
#include <CoreAudio/CoreAudio.h>
#include <span>
class ProcessTap {
    AudioBridge& bridge;
    AudioObjectID tap=0,device=0,sourceDevice=0;
    AudioDeviceIOProcID io=nullptr;
    CFTypeRef applicationDescription=nullptr;
    std::atomic<uint64_t> callbacks{0},inputBlocks{0};
    OSStatus prepare(bool beginIO,std::span<const AudioObjectID> targets);
    static OSStatus callback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void*);
public:
    explicit ProcessTap(AudioBridge& b):bridge(b){}
    ~ProcessTap(){stop();}
    OSStatus start(bool beginIO=true);
    OSStatus startApplication(std::span<const AudioObjectID> targets,bool beginIO=true);
    OSStatus resume();
    OSStatus updateApplication(std::span<const AudioObjectID> targets);
    void stop();
    bool sourceIsCurrent() const;
    AudioDeviceID sourceID() const{return sourceDevice;}
    AudioDeviceID aggregateID() const{return device;}
    uint64_t callbackCount() const{return callbacks.load(std::memory_order_relaxed);}
    uint64_t inputBlockCount() const{return inputBlocks.load(std::memory_order_relaxed);}
};
