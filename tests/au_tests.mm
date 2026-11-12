#include "../src/plugins/AURack.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <numbers>
int main() {
    auto choices=scanAUEffects();
    std::cout<<"AUv2 effect candidates: "<<choices.size()<<std::endl;
    AUChoice c{{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple AUHipass"};
    AUEffect effect(c);
    OSStatus result=effect.prepare(48000);
    if(result) { std::cerr<<"AU initialization unavailable: "<<result<<std::endl; return 2; }
    assert(AudioUnitSetParameter(effect.handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,2000,0)==0);
    float l[256],r[256]; double energy=0;
    for(int block=0;block<200;++block) {
        for(int i=0;i<256;++i) {l[i]=0.1*std::sin(2*std::numbers::pi*100*(block*256+i)/48000); r[i]=0;}
        effect.process(l,r,256); assert(effect.error==0);
        for(int i=0;i<256;++i) {assert(std::isfinite(l[i]) && r[i]==0); if(block>100) energy+=l[i]*l[i];}
    }
    assert(std::sqrt(energy/(99*256))<0.01);
    effect.bypass=true; for(int i=0;i<256;++i) {l[i]=0.25;r[i]=-0.5;} effect.process(l,r,256);
    assert(l[0]==0.25 && r[0]==-0.5);
    auto state=effect.copyState(); assert(state);
    AUEffect restored(c); assert(restored.prepare(48000)==0); assert(restored.restore(state)==0); CFRelease(state);
    AudioUnitParameterValue value=0;
    assert(AudioUnitGetParameter(restored.handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,&value)==0); assert(std::abs(value-2000)<1);
    assert(restored.prepare(44100)==0);
    assert(AudioUnitGetParameter(restored.handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,&value)==0 && std::abs(value-2000)<1);
    assert(restored.latency()>=0);
    AURack rack;
    for(int i=0;i<2;++i) rack.slots.push_back(std::make_unique<AUEffect>(c));
    assert(rack.prepare(96000)==0); for(auto& slot:rack.slots) assert(slot->error==0);
    std::vector<float> left(8192,0.1),right(8192,-0.1); rack.process(left.data(),right.data(),left.size());
    for(auto& slot:rack.slots) assert(slot->error==0);
    AUEffect missing({{kAudioUnitType_Effect,'zzzz','zzzz',0,0},"Missing"}); assert(missing.prepare(48000)!=0);
    l[0]=0.3;r[0]=0.2; missing.process(l,r,1); assert(l[0]==0.3f && r[0]==0.2f);
    bool factoryTested=false;
    for(OSType subtype:std::array<OSType,4>{kAudioUnitSubType_DynamicsProcessor,kAudioUnitSubType_MatrixReverb,kAudioUnitSubType_MultiBandCompressor,kAudioUnitSubType_Delay}) {
        AUEffect candidate({{kAudioUnitType_Effect,subtype,kAudioUnitManufacturer_Apple,0,0},"Apple factory preset test"});
        if(candidate.prepare(48000))continue;
        auto presets=candidate.factoryPresets();
        std::cout<<"Factory presets for "<<subtype<<": "<<presets.size()<<std::endl;
        if(presets.empty())continue;
        assert(candidate.applyFactoryPreset(presets.front().number)==0);
        AUPreset current{};UInt32 size=sizeof(current);
        assert(AudioUnitGetProperty(candidate.handle(),kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&current,&size)==0);
        assert(current.presetNumber==presets.front().number);if(current.presetName)CFRelease(current.presetName);
        assert(candidate.applyFactoryPreset(-2147483647)!=0);
        float left[256]{},right[256]{};left[0]=.1;candidate.process(left,right,256);assert(candidate.error==0);
        for(int i=0;i<256;++i)assert(std::isfinite(left[i])&&std::isfinite(right[i]));
        auto state=candidate.copyState();assert(state);assert(candidate.restore(state)==0);CFRelease(state);
        factoryTested=true;break;
    }
    assert(factoryTested);
    std::cout<<"PASS: Apple AU render/parameter response, bypass, state roundtrip, sample-rate reprepare, latency, multiple instances/block splitting, missing-plugin dry fallback\n";
}
