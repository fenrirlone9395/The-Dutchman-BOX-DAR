#pragma once
#include "AudioBridge.hpp"
#include <CoreAudio/CoreAudio.h>
class ProcessTap {
    AudioBridge& bridge;
    AudioObjectID tap=0,device=0,sourceDevice=0;
    AudioDeviceIOProcID io=nullptr;
    static OSStatus callback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void*);
public:
    explicit ProcessTap(AudioBridge& b):bridge(b){}
    ~ProcessTap(){stop();}
    OSStatus start(bool beginIO=true);
    OSStatus resume();
    void stop();
    bool sourceIsCurrent() const;
    AudioDeviceID sourceID() const{return sourceDevice;}
    AudioDeviceID aggregateID() const{return device;}
};
