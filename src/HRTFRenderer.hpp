#pragma once
#include "BlockProcessor.hpp"
#include "SpatialDSP.hpp"
#include <AudioToolbox/AudioToolbox.h>

// Set up and dispose the Apple mixer while output is stopped. Only its render
// and parameter APIs are called from the audio thread.
class HRTFRenderer final : public SpatialRenderer {
    static constexpr UInt32 blockSize=512;
    AudioUnit unit=nullptr;
    const float* sources[2]{};
    UInt32 sourceFrames=0;
    double sampleTime=0, sampleRate=48000;
    float wet=0, angle=SpatialParameters::defaultHRTFAngle;
    std::array<float,blockSize> left{},right{};

    static OSStatus input(void* context,AudioUnitRenderActionFlags*,const AudioTimeStamp*,UInt32 bus,UInt32 frames,AudioBufferList* data) {
        auto& self=*static_cast<HRTFRenderer*>(context);
        if(bus>=2 || frames!=self.sourceFrames || !data || data->mNumberBuffers!=1)return kAudio_ParamError;
        auto& buffer=data->mBuffers[0];
        if(buffer.mData){
            if(buffer.mDataByteSize<frames*sizeof(float))return kAudio_ParamError;
            std::copy_n(self.sources[bus],frames,static_cast<float*>(buffer.mData));
        }else buffer.mData=const_cast<float*>(self.sources[bus]);
        buffer.mNumberChannels=1;buffer.mDataByteSize=frames*sizeof(float);
        return noErr;
    }
    OSStatus position(float value) {
        OSStatus status=AudioUnitSetParameter(unit,kSpatialMixerParam_Azimuth,kAudioUnitScope_Input,0,-value,0);
        return status?status:AudioUnitSetParameter(unit,kSpatialMixerParam_Azimuth,kAudioUnitScope_Input,1,value,0);
    }
public:
    HRTFRenderer()=default;
    HRTFRenderer(const HRTFRenderer&)=delete;
    HRTFRenderer& operator=(const HRTFRenderer&)=delete;
    ~HRTFRenderer(){close();}
    void close(){
        if(unit){AudioUnitUninitialize(unit);AudioComponentInstanceDispose(unit);unit=nullptr;}
        wet=0;sampleTime=0;
    }
    bool blending()const override{return wet>0;}
    OSStatus prepare(double rate) {
        close();sampleRate=rate;angle=SpatialParameters::defaultHRTFAngle;
        AudioComponentDescription desc{kAudioUnitType_Mixer,kAudioUnitSubType_SpatialMixer,kAudioUnitManufacturer_Apple,0,0};
        auto component=AudioComponentFindNext(nullptr,&desc);
        if(!component)return kAudioUnitErr_FailedInitialization;
        OSStatus status=AudioComponentInstanceNew(component,&unit);
        if(status)return status;
        auto property=[&](AudioUnitPropertyID id,AudioUnitScope scope,UInt32 bus,UInt32 value){
            if(!status)status=AudioUnitSetProperty(unit,id,scope,bus,&value,sizeof(value));
        };
        property(kAudioUnitProperty_ElementCount,kAudioUnitScope_Input,0,2);
        property(kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,blockSize);
        property(kAudioUnitProperty_SpatialMixerOutputType,kAudioUnitScope_Global,0,kSpatialMixerOutputType_Headphones);
        property(kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode,kAudioUnitScope_Global,0,kSpatialMixerPersonalizedHRTFMode_Off);
        property(kAudioUnitProperty_UsesInternalReverb,kAudioUnitScope_Global,0,0);
        auto format=[&](AudioUnitScope scope,UInt32 bus,UInt32 channels){
            AudioStreamBasicDescription asbd{rate,kAudioFormatLinearPCM,AudioFormatFlags(kAudioFormatFlagsNativeFloatPacked)|kAudioFormatFlagIsNonInterleaved,4,1,4,channels,32,0};
            if(!status)status=AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,scope,bus,&asbd,sizeof(asbd));
        };
        format(kAudioUnitScope_Output,0,2);
        for(UInt32 bus=0;bus<2;++bus){
            format(kAudioUnitScope_Input,bus,1);
            property(kAudioUnitProperty_SpatializationAlgorithm,kAudioUnitScope_Input,bus,kSpatializationAlgorithm_HRTFHQ);
            property(kAudioUnitProperty_SpatialMixerSourceMode,kAudioUnitScope_Input,bus,kSpatialMixerSourceMode_PointSource);
            property(kAudioUnitProperty_SpatialMixerRenderingFlags,kAudioUnitScope_Input,bus,kSpatialMixerRenderingFlags_InterAuralDelay);
            AURenderCallbackStruct cb{input,this};
            if(!status)status=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,bus,&cb,sizeof(cb));
        }
        if(!status)status=AudioUnitInitialize(unit);
        for(UInt32 bus=0;bus<2&&!status;++bus)status=AudioUnitSetParameter(unit,kSpatialMixerParam_Distance,kAudioUnitScope_Input,bus,1.5f,0);
        if(!status)status=position(angle);
        if(status)close();
        return status;
    }
    OSStatus process(float* l,float* r,size_t frames,bool active,float targetAngle) override {
        if(!unit||(!active&&!blending()))return noErr;
        if(!std::isfinite(targetAngle))targetAngle=SpatialParameters::defaultHRTFAngle;
        targetAngle=std::clamp(targetAngle,10.f,75.f);
        for(size_t offset=0;offset<frames;offset+=blockSize){
            const UInt32 count=UInt32(std::min<size_t>(blockSize,frames-offset));
            if(active){
                float next=angle+std::clamp(targetAngle-angle,-float(360*count/sampleRate),float(360*count/sampleRate));
                if(next!=angle){if(auto status=position(next)){wet=0;return status;}angle=next;}
            }
            sources[0]=l+offset;sources[1]=r+offset;sourceFrames=count;
            struct StereoBuffers {UInt32 count;AudioBuffer buffers[2];} output{2,{{1,count*4,left.data()},{1,count*4,right.data()}}};
            AudioTimeStamp stamp{};stamp.mFlags=kAudioTimeStampSampleTimeValid;stamp.mSampleTime=sampleTime;
            AudioUnitRenderActionFlags flags=0;
            OSStatus status=AudioUnitRender(unit,&flags,&stamp,0,count,reinterpret_cast<AudioBufferList*>(&output));
            sampleTime+=count;
            if(status){wet=0;return status;}
            const bool silence=(flags&kAudioUnitRenderAction_OutputIsSilence)!=0;
            if(!silence && (output.count!=2 || !output.buffers[0].mData || !output.buffers[1].mData ||
                output.buffers[0].mDataByteSize<count*sizeof(float) || output.buffers[1].mDataByteSize<count*sizeof(float))){
                wet=0;return kAudio_ParamError;
            }
            const auto* renderedL=static_cast<const float*>(output.buffers[0].mData);
            const auto* renderedR=static_cast<const float*>(output.buffers[1].mData);
            if(!silence)for(UInt32 i=0;i<count;++i)
                if(!std::isfinite(renderedL[i])||!std::isfinite(renderedR[i])){wet=0;return kAudio_ParamError;}
            const float step=float(1/(sampleRate*.02));
            for(UInt32 i=0;i<count;++i){
                wet=std::clamp(wet+(active?step:-step),0.f,1.f);
                l[offset+i]+=((silence?0.f:renderedL[i])-l[offset+i])*wet;
                r[offset+i]+=((silence?0.f:renderedR[i])-r[offset+i])*wet;
            }
        }
        return noErr;
    }
};
