#pragma once
#include "../BlockProcessor.hpp"
#include "../DSP.hpp"
#include <AudioToolbox/AudioToolbox.h>
#include <array>
#include <atomic>
#include <memory>
#include <string>
#include <vector>
struct AUFactoryPreset { SInt32 number; std::string name; };
struct AUChoice { AudioComponentDescription description; std::string name; };
std::vector<AUChoice> scanAUEffects();
class AUEffect {
    static constexpr UInt32 maximumFrames=4096;
    AudioUnit unit=nullptr;
    std::array<float,maximumFrames> scratchL{},scratchR{},inputL{},inputR{};
    float *sourceL=nullptr,*sourceR=nullptr;
    UInt32 sourceFrames=0;
    double time=0;
    bool initialized=false;
    static OSStatus input(void*,AudioUnitRenderActionFlags*,const AudioTimeStamp*,UInt32,UInt32,AudioBufferList*);
public:
    struct PresetParameter { AudioUnitParameterID id; AudioUnitScope scope; AudioUnitElement element; float value; };
    std::string presetKey,presetName;
    bool presetModified=false;
    std::vector<PresetParameter> presetBaseline;
    void markPreset(std::string key,std::string name); // Main thread, output paused.
    void refreshPresetModified(); // Main thread; reads parameter values only, never serializes state.
    StereoMeter outputMeter;
    AUChoice choice;
    std::atomic<bool> bypass{false};
    std::atomic<OSStatus> error{0};
    explicit AUEffect(AUChoice c):choice(std::move(c)){}
    ~AUEffect();
    OSStatus prepare(double);
    void process(float*,float*,UInt32);
    AudioUnit handle() const { return unit; }
    double latency() const;
    std::vector<AUFactoryPreset> factoryPresets() const;
    OSStatus applyFactoryPreset(SInt32 number); // Output must be paused.
    CFPropertyListRef copyState() const; // Caller owns result. Only while stopped.
    OSStatus restore(CFPropertyListRef);
};
class AURack : public BlockProcessor {
public:
    static constexpr size_t maximumSlots=8;
    std::vector<std::unique_ptr<AUEffect>> slots; // Main-thread mutations only while stopped.
    int prepare(double rate) override;
    void process(float*,float*,size_t) override;
};
