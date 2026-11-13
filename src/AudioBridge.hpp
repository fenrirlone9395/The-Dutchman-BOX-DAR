#pragma once
#include "DSP.hpp"
#include "SpatialDSP.hpp"
#include "ClockRateAdapter.hpp"
#include "EngineDiagnostics.hpp"
#include "RecoveryDiagnostics.hpp"
#include "BlockProcessor.hpp"
#include <array>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <cstdint>

// One capture producer, one output consumer. Reset only after both stop.
class AudioBridge {
    static constexpr uint64_t capacity = 32768;
    std::array<std::array<float, 2>, capacity> samples{};
    alignas(64) std::atomic<uint64_t> write{0};
    alignas(64) std::atomic<uint64_t> read{0};
    double phase = 0;
    bool primed = false;
    float gain = 0;
    uint64_t outputBlocks=0,lastCaptureSequence=0;
    InternalDSP dsp;
    CrossfeedDSP spatial;
public:
    EndpointActivity captureActivity,outputActivity;
    RecoveryEvents recoveryEvents;
    std::atomic<uint64_t> initialZeroInputFrames{0},recoveryZeroInputFrames{0},lastPlannedResume{0},lastRenderNS{0};
    TimestampMailbox captureTimestamp,outputTimestamp;
    CallbackTiming callbackTiming;
    ClockRateAdapter rateAdapter;
    std::atomic<double> feedForwardPPM{0};
    std::atomic<bool> muted{true};
    DSPParameters parameters;
    SpatialParameters spatialParameters;
    std::atomic<double> captureRate{48000};
    BlockProcessor* rack=nullptr; // Lifetime owned by app, replaced only with output stopped.
    StereoMeter inputMeter, outputMeter;
    std::atomic<float> gainReduction{0};
    std::atomic<float> inputPeak{0}, outputPeak{0};
    std::atomic<uint64_t> underruns{0}, overruns{0}, invalid{0};
    static_assert(std::atomic<uint64_t>::is_always_lock_free);
    static_assert(std::atomic<float>::is_always_lock_free);
    void fadeIn() { gain=0; } // Call only while output is paused.
    void reset() {
        write = 0; read = 0; phase = 0; primed = false; gain = 0;
        outputBlocks=lastCaptureSequence=0;captureActivity.reset();outputActivity.reset();recoveryEvents.reset();initialZeroInputFrames=0;recoveryZeroInputFrames=0;lastPlannedResume=0;lastRenderNS=0;
        rateAdapter.reset(); feedForwardPPM=0;captureTimestamp.reset();outputTimestamp.reset();callbackTiming.reset();
        dsp.reset(); spatial.reset(); inputMeter.reset(); outputMeter.reset(); gainReduction=0;
        inputPeak = 0; outputPeak = 0; underruns = 0; overruns = 0; invalid = 0;
    }
    uint64_t queued() const { auto r=read.load(); auto w=write.load(); return w >= r ? w-r : 0; }
    void push(const float* l, const float* r, size_t frames, size_t stride) {
        uint64_t sequence=captureTimestamp.sequence.load(std::memory_order_acquire);double sample=std::numeric_limits<double>::quiet_NaN();
        if(sequence && sequence!=lastCaptureSequence){sample=captureTimestamp.sample.load(std::memory_order_relaxed);lastCaptureSequence=sequence;}
        captureActivity.observe(mach_absolute_time(),uint32_t(frames),captureRate.load(std::memory_order_relaxed),sample);
        auto w = write.load(std::memory_order_relaxed);
        auto rd = read.load(std::memory_order_acquire);
        if (frames > capacity-(w-rd)) { ++overruns; return; }
        float peak=0,pl=0,pr=0;
        for(size_t i=0;i<frames;++i) {
            float a=l[i*stride], b=r[i*stride];
            if(!std::isfinite(a) || !std::isfinite(b)) { a=b=0; ++invalid; }
            samples[(w+i)%capacity]={a,b};
            pl=std::max(pl,std::abs(a)); pr=std::max(pr,std::abs(b));
            peak=std::max(peak,std::max(std::abs(a),std::abs(b)));
        }
        StereoMeter::maximum(inputPeak,peak); inputMeter.publish(pl,pr);
        write.store(w+frames,std::memory_order_release);
    }
    // Bounded, allocation-free linear SRC, with gentle occupancy-based clock correction.
    // Replace with band-limited SRC before production listening-quality release.
    void render(float* l,float* r,size_t frames,double outputRate) {
        ++outputBlocks;uint64_t renderBegan=mach_absolute_time();
        std::array<RecoveryEvent,3> pendingEvents{};size_t pendingCount=0;
        auto rd=read.load(std::memory_order_relaxed);
        auto w=write.load(std::memory_order_acquire);
        bool legacy=rateAdapter.mode()==RateMode::Legacy;
        constexpr uint64_t target=2048;
        if(legacy && w-rd > 8192) { rd=w-target; phase=0; primed=false; ++overruns; }
        if(legacy && !primed && w-rd>=target) primed=true;
        double correction=std::clamp((double(w-rd)-target)/double(target)*0.002,-0.005,0.005);
        double step=captureRate.load()/outputRate*(1+correction);
        if(legacy){auto& t=rateAdapter.telemetry;t.ratio=step;t.ppm=correction*1e6;t.fill=double(w-rd);t.minFill=std::min(t.minFill.load(std::memory_order_relaxed),double(w-rd));t.maxFill=std::max(t.maxFill.load(std::memory_order_relaxed),double(w-rd));}
        float peak=0,pl=0,pr=0; bool starved=false;
        dsp.begin(parameters,outputRate,frames);
        spatial.begin(spatialParameters,outputRate);
        auto before=rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed);
        bool wasPrimed=rateAdapter.isPrimed();
        auto observeRecovery=[&](RecoveryReason reason,size_t frame){
            RecoveryEvent event;event.reason=reason;event.host=mach_absolute_time();event.outputBlock=outputBlocks;event.frames=uint32_t(frames);event.frameInBlock=uint32_t(frame);event.snapshotWrite=w;event.liveWrite=write.load(std::memory_order_acquire);event.cursor=rateAdapter.consumed();event.phase=rateAdapter.fractionalPosition();
            auto& t=rateAdapter.telemetry;event.fillAtEntry=t.fill.load();event.ratio=rateAdapter.stepAt(frame,frames);event.correctionPPM=t.ppm.load();event.feedForwardPPM=t.feedForwardPPM.load();event.filteredFill=t.filteredFill.load();event.proportionalPPM=t.proportionalPPM.load();event.integralPPM=t.integralPPM.load();event.desiredPPM=t.desiredPPM.load();
            event.neededInput=uint32_t(rateAdapter.requiredInput(event.ratio));event.zeroInputFrames=reason==RecoveryReason::InputLookaheadShortage?uint32_t(frames-frame):0;
            auto captureEntry=captureActivity.lastEntry.load(std::memory_order_acquire);event.captureAgeTicks=captureEntry&&event.host>=captureEntry?event.host-captureEntry:0;event.captureGapTicks=captureActivity.lastGapTicks.load();event.outputGapTicks=outputActivity.lastGapTicks.load();event.captureSampleJumps=captureActivity.sampleJumps.load();event.outputSampleJumps=outputActivity.sampleJumps.load();event.previousRenderNS=lastRenderNS.load();event.lastPlannedResume=lastPlannedResume.load();if(pendingCount<pendingEvents.size())pendingEvents[pendingCount++]=event;
        };
        if(!legacy) {
            rateAdapter.begin(w,frames,feedForwardPPM.load(std::memory_order_relaxed));
            if(rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed)!=before){++overruns;observeRecovery(RecoveryReason::ExcessBacklog,0);}
            if(!wasPrimed&&rateAdapter.isPrimed()&&rateAdapter.telemetry.recoveries.load())observeRecovery(RecoveryReason::Reprimed,0);
        }
        before=rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed);
        auto reader=[&](int64_t n){return n<0?std::array<float,2>{0,0}:samples[uint64_t(n)%capacity];};
        bool observedShortage=false;uint64_t zeroInputs=0;
        for(size_t i=0;i<frames;++i) {
            float a=0,b=0;
            if(!legacy) {
                bool available=rateAdapter.next(w,i,frames,reader,a,b);
                if(!available){++zeroInputs;if(!observedShortage){if(rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed)!=before)observeRecovery(RecoveryReason::InputLookaheadShortage,i);observedShortage=true;}}
            }
            else if(primed && w-rd>=2 && double(w-rd)>phase+step+1) {
                auto &x=samples[rd%capacity], &y=samples[(rd+1)%capacity];
                a=x[0]+(y[0]-x[0])*phase; b=x[1]+(y[1]-x[1])*phase;
                phase+=step; auto used=uint64_t(phase); rd+=used; phase-=used;
            } else if(primed) { primed=false; phase=0; starved=true; }
            dsp.processInput(a,b);
            l[i]=a; r[i]=b;
        }
        if(rack) rack->process(l,r,frames);
        for(size_t i=0;i<frames;++i) {
            float a=l[i],b=r[i];
            spatial.process(a,b);
            dsp.processMaster(a,b);
            if(!std::isfinite(a)||!std::isfinite(b)) { a=b=0; dsp.reset(); muted=true; ++invalid; }
            if(muted.load(std::memory_order_relaxed)) gain=0;
            else gain=std::min(1.0f,gain+1.0f/512);
            l[i]=a*gain; r[i]=b*gain;
            pl=std::max(pl,std::abs(l[i])); pr=std::max(pr,std::abs(r[i]));
            peak=std::max(peak,std::max(std::abs(l[i]),std::abs(r[i])));
        }
        if(!legacy) {
            if(zeroInputs){if(rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed))recoveryZeroInputFrames.fetch_add(zeroInputs,std::memory_order_relaxed);else initialZeroInputFrames.fetch_add(zeroInputs,std::memory_order_relaxed);}
            rd=rateAdapter.retainedRead();
            if(rateAdapter.telemetry.recoveries.load(std::memory_order_relaxed)!=before)++underruns;
        }
        if(starved) ++underruns;
        StereoMeter::maximum(outputPeak,peak); outputMeter.publish(pl,pr);
        StereoMeter::maximum(gainReduction,dsp.reduction);
        read.store(rd,std::memory_order_release);
        if(pendingCount){uint64_t elapsed=uint64_t((mach_absolute_time()-renderBegan)*callbackTiming.nanosPerTick);for(size_t i=0;i<pendingCount;++i){pendingEvents[i].currentRenderNS=elapsed;recoveryEvents.push(pendingEvents[i]);}}
    }
};
