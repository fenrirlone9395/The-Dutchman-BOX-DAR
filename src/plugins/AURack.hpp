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
class RackEffect {
public:
    struct PresetParameter { AudioUnitParameterID id; AudioUnitScope scope; AudioUnitElement element; float value; };
    std::string presetKey,presetName;
    bool presetModified=false;
    std::vector<PresetParameter> presetBaseline;
    virtual void markPreset(std::string key,std::string name) { presetKey=std::move(key);presetName=std::move(name);presetModified=false; } // Main thread, output paused.
    virtual void refreshPresetModified() {} // Main thread; reads parameter values only, never serializes state.
    StereoMeter outputMeter;
    AUChoice choice;
    std::atomic<bool> bypass{false};
    std::atomic<OSStatus> error{0};
    explicit RackEffect(AUChoice c):choice(std::move(c)){}
    virtual ~RackEffect()=default;
    virtual OSStatus prepare(double)=0;
    virtual void process(float*,float*,UInt32)=0;
    virtual AudioUnit handle() const { return nullptr; }
    virtual double latency() const=0;
    virtual std::vector<AUFactoryPreset> factoryPresets() const { return {}; }
    virtual OSStatus applyFactoryPreset(SInt32) { return kAudio_ParamError; }
    virtual CFPropertyListRef copyState() const=0;
    virtual OSStatus restore(CFPropertyListRef)=0;
    virtual const char* errorDetail() const { return ""; }
    virtual bool isVST3() const { return false; }
    virtual bool showEditor() { return false; }
    virtual void closeEditor() {}
    virtual void idle() {}
};
class AUEffect : public RackEffect {
    static constexpr UInt32 maximumFrames=4096;
    AudioUnit unit=nullptr;
    std::array<float,maximumFrames> scratchL{},scratchR{},inputL{},inputR{};
    float *sourceL=nullptr,*sourceR=nullptr;
    UInt32 sourceFrames=0;
    double time=0;
    bool initialized=false;
    static OSStatus input(void*,AudioUnitRenderActionFlags*,const AudioTimeStamp*,UInt32,UInt32,AudioBufferList*);
public:
    explicit AUEffect(AUChoice c):RackEffect(std::move(c)){}
    ~AUEffect() override;
    void markPreset(std::string,std::string) override;
    void refreshPresetModified() override;
    OSStatus prepare(double) override;
    void process(float*,float*,UInt32) override;
    AudioUnit handle() const override { return unit; }
    double latency() const override;
    std::vector<AUFactoryPreset> factoryPresets() const override;
    OSStatus applyFactoryPreset(SInt32 number) override; // Output must be paused.
    CFPropertyListRef copyState() const override; // Caller owns result. Only while stopped.
    OSStatus restore(CFPropertyListRef) override;
};
class AURack : public BlockProcessor {
public:
    static constexpr size_t maximumSlots=8;
    std::vector<std::unique_ptr<RackEffect>> slots; // Fixed slot indices; nullptr is an empty slot. Main-thread mutations only while stopped.
    int prepare(double rate) override;
    void process(float*,float*,size_t) override;
};
