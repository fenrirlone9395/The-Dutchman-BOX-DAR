#pragma once
#include <array>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <limits>
#include <mach/mach_time.h>

// Observations only. One writer per endpoint, no clock/rate decisions here.
struct EndpointActivity {
    std::atomic<uint64_t> callbacks{0},framesSeen{0},lastEntry{0},lastGapTicks{0},maxGapTicks{0},longGaps{0},sampleJumps{0};
    std::atomic<double> lastSampleGap{0};
    uint32_t previousFrames=0;
    double previousSample=std::numeric_limits<double>::quiet_NaN();
    double nanosPerTick=1;
    void prepare(){mach_timebase_info_data_t t{};mach_timebase_info(&t);nanosPerTick=double(t.numer)/t.denom;}
    void reset(){callbacks=0;framesSeen=0;lastEntry=0;lastGapTicks=0;maxGapTicks=0;longGaps=0;sampleJumps=0;lastSampleGap=0;previousFrames=0;previousSample=std::numeric_limits<double>::quiet_NaN();}
    void observe(uint64_t now,uint32_t frames,double rate,double sample=std::numeric_limits<double>::quiet_NaN()){
        uint64_t previous=lastEntry.load(std::memory_order_relaxed);
        if(previous && now>=previous){uint64_t gap=now-previous;lastGapTicks=gap;maxGapTicks=std::max(maxGapTicks.load(std::memory_order_relaxed),gap);if(rate>0 && gap*nanosPerTick>1.5*previousFrames/rate*1e9)++longGaps;}
        if(std::isfinite(sample)&&std::isfinite(previousSample)){double gap=sample-previousSample-previousFrames;lastSampleGap=gap;if(std::abs(gap)>.5)++sampleJumps;}else lastSampleGap=std::numeric_limits<double>::quiet_NaN();
        previousSample=sample;previousFrames=frames;framesSeen.fetch_add(frames,std::memory_order_relaxed);lastEntry.store(now,std::memory_order_release);callbacks.fetch_add(1,std::memory_order_relaxed);
    }
};
enum class RecoveryReason:uint32_t { InputLookaheadShortage, ExcessBacklog, Reprimed };
struct RecoveryEvent {
    RecoveryReason reason{};
    uint32_t frames=0,frameInBlock=0,neededInput=0,zeroInputFrames=0;
    uint64_t host=0,outputBlock=0,snapshotWrite=0,liveWrite=0,cursor=0;
    uint64_t captureAgeTicks=0,captureGapTicks=0,outputGapTicks=0,previousRenderNS=0,currentRenderNS=0,lastPlannedResume=0;
    uint64_t captureSampleJumps=0,outputSampleJumps=0;
    double phase=0,fillAtEntry=0,ratio=1,correctionPPM=0,feedForwardPPM=0,filteredFill=0,proportionalPPM=0,integralPPM=0,desiredPPM=0;
};
// Fixed SPSC queue: render thread -> UI. Full means discard observation, never wait.
class RecoveryEvents {
    std::array<RecoveryEvent,128> events{};
    alignas(64) std::atomic<uint64_t> written{0};
    alignas(64) std::atomic<uint64_t> read{0};
public:
    std::atomic<uint64_t> dropped{0};
    void reset(){written=0;read=0;dropped=0;} // Both endpoints stopped.
    bool push(const RecoveryEvent& event){auto w=written.load(std::memory_order_relaxed);auto r=read.load(std::memory_order_acquire);if(w-r>=events.size()){++dropped;return false;}events[w%events.size()]=event;written.store(w+1,std::memory_order_release);return true;}
    bool pop(RecoveryEvent& event){auto r=read.load(std::memory_order_relaxed);auto w=written.load(std::memory_order_acquire);if(r==w)return false;event=events[r%events.size()];read.store(r+1,std::memory_order_release);return true;}
};
