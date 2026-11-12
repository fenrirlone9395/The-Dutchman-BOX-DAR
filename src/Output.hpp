#pragma once
#include "AudioBridge.hpp"
#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudio.h>
#include <string>
#include <vector>
struct OutputDevice { AudioDeviceID id; std::string name; };
std::vector<OutputDevice> outputDevices();
class Output {
    AudioUnit unit=nullptr;
    AudioBridge& bridge;
    static OSStatus callback(void*,AudioUnitRenderActionFlags*,const AudioTimeStamp*,UInt32,UInt32,AudioBufferList*);
public:
    double rate=0;
    UInt32 bufferFrames=0;
    explicit Output(AudioBridge& b):bridge(b){}
    ~Output(){ stop(); }
    OSStatus start(AudioDeviceID);
    void stop();
    void pause();
    OSStatus resume();
};
