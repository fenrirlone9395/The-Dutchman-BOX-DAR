#include "AURack.hpp"
#import <Foundation/Foundation.h>
#include <algorithm>
#include <cmath>
#include <cstring>
std::vector<AUChoice> scanAUEffects() {
    std::vector<AUChoice> result;
    AudioComponentDescription query{kAudioUnitType_Effect,0,0,0,0};
    AudioComponent component=nullptr;
    while((component=AudioComponentFindNext(component,&query))) {
        AudioComponentDescription d{}; if(AudioComponentGetDescription(component,&d)) continue;
        if(d.componentFlags & kAudioComponentFlag_IsV3AudioUnit) continue; // v2 Cocoa editors in this milestone.
        CFStringRef name=nullptr;
        if(!AudioComponentCopyName(component,&name) && name) {
            result.push_back({d,[(__bridge NSString*)name UTF8String]}); CFRelease(name);
        }
    }
    std::sort(result.begin(),result.end(),[](auto& a,auto& b){return a.name<b.name;}); return result;
}
AUEffect::~AUEffect() { if(unit) { if(initialized) AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit); } }
OSStatus AUEffect::input(void* context,AudioUnitRenderActionFlags*,const AudioTimeStamp*,UInt32 bus,UInt32 frames,AudioBufferList* data) {
    auto* self=static_cast<AUEffect*>(context);
    if(bus || frames>self->sourceFrames || data->mNumberBuffers!=2) return kAudio_ParamError;
    float* src[2]{self->sourceL,self->sourceR};
    for(UInt32 ch=0;ch<2;++ch) {
        auto& b=data->mBuffers[ch];
        if(b.mData) { if(b.mDataByteSize<frames*4) return kAudio_ParamError; memcpy(b.mData,src[ch],frames*4); }
        else b.mData=src[ch];
        b.mDataByteSize=frames*4; b.mNumberChannels=1;
    }
    return noErr;
}
OSStatus AUEffect::prepare(double rate) {
    error=0; time=0;
    if(!unit) {
        auto component=AudioComponentFindNext(nullptr,&choice.description);
        if(!component) return error=kAudio_ParamError;
        OSStatus s=AudioComponentInstanceNew(component,&unit); if(s) return error=s;
    }
    if(initialized) { AudioUnitUninitialize(unit); initialized=false; }
    UInt32 count=0,size=sizeof(count);
    for(auto scope:{kAudioUnitScope_Input,kAudioUnitScope_Output}) {
        OSStatus s=AudioUnitGetProperty(unit,kAudioUnitProperty_ElementCount,scope,0,&count,&size);
        if(s || count!=1) return error=s?s:kAudioUnitErr_FormatNotSupported;
    }
    AudioStreamBasicDescription f{rate,kAudioFormatLinearPCM,AudioFormatFlags(kAudioFormatFlagsNativeFloatPacked)|AudioFormatFlags(kAudioFormatFlagIsNonInterleaved),4,1,4,2,32,0};
    for(auto scope:{kAudioUnitScope_Input,kAudioUnitScope_Output}) {
        OSStatus s=AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,scope,0,&f,sizeof(f)); if(s) return error=s;
    }
    UInt32 max=maximumFrames;
    OSStatus s=AudioUnitSetProperty(unit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&max,sizeof(max)); if(s) return error=s;
    AURenderCallbackStruct cb{input,this};
    s=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,sizeof(cb)); if(s) return error=s;
    s=AudioUnitInitialize(unit); if(s) return error=s;
    initialized=true; return noErr;
}
void AUEffect::process(float* l,float* r,UInt32 frames) {
    if(bypass.load() || error.load() || !initialized) { time+=frames; return; }
    if(frames>maximumFrames) { error=kAudioUnitErr_TooManyFramesToProcess; return; }
    memcpy(inputL.data(),l,frames*4); memcpy(inputR.data(),r,frames*4);
    sourceL=inputL.data(); sourceR=inputR.data(); sourceFrames=frames;
    struct StereoList { UInt32 count; AudioBuffer buffers[2]; } list{2,{{1,frames*4,scratchL.data()},{1,frames*4,scratchR.data()}}};
    AudioTimeStamp stamp{}; stamp.mSampleTime=time; stamp.mFlags=kAudioTimeStampSampleTimeValid;
    AudioUnitRenderActionFlags flags=0;
    OSStatus s=AudioUnitRender(unit,&flags,&stamp,0,frames,reinterpret_cast<AudioBufferList*>(&list)); time+=frames;
    if(s) { error=s; return; } // Preserve dry signal; failed slots remain bypassed until restart.
    if(flags & kAudioUnitRenderAction_OutputIsSilence) { memset(l,0,frames*4); memset(r,0,frames*4); return; }
    if(list.count!=2 || !list.buffers[0].mData || !list.buffers[1].mData || list.buffers[0].mDataByteSize<frames*4 || list.buffers[1].mDataByteSize<frames*4) { error=kAudio_ParamError; return; }
    auto* a=static_cast<float*>(list.buffers[0].mData); auto* b=static_cast<float*>(list.buffers[1].mData);
    for(UInt32 i=0;i<frames;++i) if(!std::isfinite(a[i]) || !std::isfinite(b[i])) { error=kAudio_ParamError; return; }
    memcpy(l,a,frames*4); memcpy(r,b,frames*4);
}
double AUEffect::latency() const {
    Float64 value=0; UInt32 size=sizeof(value);
    if(!unit || AudioUnitGetProperty(unit,kAudioUnitProperty_Latency,kAudioUnitScope_Global,0,&value,&size)) return -1;
    return std::isfinite(value)&&value>=0?value:-1;
}
CFPropertyListRef AUEffect::copyState() const {
    CFPropertyListRef state=nullptr; UInt32 size=sizeof(state);
    if(!unit || AudioUnitGetProperty(unit,kAudioUnitProperty_ClassInfo,kAudioUnitScope_Global,0,&state,&size)) return nullptr;
    return state;
}
OSStatus AUEffect::restore(CFPropertyListRef state) {
    if(!unit || !state || CFGetTypeID(state)!=CFDictionaryGetTypeID()) return kAudio_ParamError;
    OSStatus s=AudioUnitSetProperty(unit,kAudioUnitProperty_ClassInfo,kAudioUnitScope_Global,0,&state,sizeof(state));
    if(s) error=s; return s;
}
int AURack::prepare(double rate) { for(auto& slot:slots) slot->prepare(rate); return 0; }
void AURack::process(float* l,float* r,size_t frames) {
    for(size_t offset=0;offset<frames;offset+=4096) {
        UInt32 n=UInt32(std::min(size_t(4096),frames-offset));
        for(auto& slot:slots) {
            slot->process(l+offset,r+offset,n);
            float a=0,b=0;for(UInt32 i=0;i<n;++i){a=std::max(a,std::abs(l[offset+i]));b=std::max(b,std::abs(r[offset+i]));}
            slot->outputMeter.publish(a,b);
        }
    }
}

std::vector<AUFactoryPreset> AUEffect::factoryPresets() const {
    std::vector<AUFactoryPreset> result;
    if(!unit) return result;
    CFArrayRef presets=nullptr; UInt32 size=sizeof(presets);
    OSStatus s=AudioUnitGetProperty(unit,kAudioUnitProperty_FactoryPresets,kAudioUnitScope_Global,0,&presets,&size);
    if(!s && presets) {
        for(CFIndex i=0;i<CFArrayGetCount(presets);++i) {
            auto* preset=static_cast<const AUPreset*>(CFArrayGetValueAtIndex(presets,i));
            if(preset && preset->presetName && preset->presetNumber>=0) result.push_back({preset->presetNumber,[(__bridge NSString*)preset->presetName UTF8String]});
        }
    }
    if(presets) CFRelease(presets); return result;
}
OSStatus AUEffect::applyFactoryPreset(SInt32 number) {
    for(auto& entry:factoryPresets()) if(entry.number==number) {
        CFStringRef name=CFStringCreateWithCString(nullptr,entry.name.c_str(),kCFStringEncodingUTF8);
        AUPreset preset{entry.number,name};
        OSStatus s=AudioUnitSetProperty(unit,kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&preset,sizeof(preset));
        if(name)CFRelease(name);return s;
    }
    return kAudio_ParamError;
}

void AUEffect::markPreset(std::string key,std::string name) {
    presetKey=std::move(key);presetName=std::move(name);presetModified=false;presetBaseline.clear();
    if(!unit)return;
    for(auto scope:{kAudioUnitScope_Global,kAudioUnitScope_Input,kAudioUnitScope_Output}) {
        UInt32 elements=1,size=sizeof(elements);
        if(scope!=kAudioUnitScope_Global && AudioUnitGetProperty(unit,kAudioUnitProperty_ElementCount,scope,0,&elements,&size))continue;
        for(UInt32 element=0;element<elements;++element) {
            UInt32 bytes=0;Boolean writable=false;
            if(AudioUnitGetPropertyInfo(unit,kAudioUnitProperty_ParameterList,scope,element,&bytes,&writable) || bytes>1024*1024)continue;
            std::vector<AudioUnitParameterID> ids(bytes/sizeof(AudioUnitParameterID));
            if(ids.empty() || AudioUnitGetProperty(unit,kAudioUnitProperty_ParameterList,scope,element,ids.data(),&bytes))continue;
            for(auto id:ids) {
                AudioUnitParameterInfo info{};size=sizeof(info);
                if(AudioUnitGetProperty(unit,kAudioUnitProperty_ParameterInfo,scope,id,&info,&size))continue;
                bool editable=(info.flags&kAudioUnitParameterFlag_IsWritable) && (info.flags&kAudioUnitParameterFlag_IsReadable) && !(info.flags&kAudioUnitParameterFlag_MeterReadOnly);
                if(info.flags&kAudioUnitParameterFlag_CFNameRelease) {if(info.cfNameString)CFRelease(info.cfNameString);if(info.unit==kAudioUnitParameterUnit_CustomUnit && info.unitName)CFRelease(info.unitName);}
                float value=0;
                if(editable && !AudioUnitGetParameter(unit,id,scope,element,&value))presetBaseline.push_back({id,scope,element,value});
            }
        }
    }
}
void AUEffect::refreshPresetModified() {
    if(presetKey.empty() || !unit)return;
    bool changed=false;
    for(auto& p:presetBaseline) {
        float value=0;
        if(AudioUnitGetParameter(unit,p.id,p.scope,p.element,&value) || value!=p.value) {changed=true;break;}
    }
    presetModified=changed;
}
