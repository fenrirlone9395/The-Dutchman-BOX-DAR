#pragma once
#include <array>
#include <algorithm>
#include <atomic>
#include <bit>
#include <cmath>
#include <cstdint>
#include <string>
#include <mach/mach_time.h>
static_assert(std::atomic<double>::is_always_lock_free);
static_assert(std::atomic<uint64_t>::is_always_lock_free);
struct TimestampMailbox {
    std::atomic<uint64_t> sequence{0},host{0};std::atomic<double> sample{0};
    void publish(double s,uint64_t h){sequence.fetch_add(1,std::memory_order_relaxed);sample.store(s,std::memory_order_relaxed);host.store(h,std::memory_order_relaxed);sequence.fetch_add(1,std::memory_order_release);}
    bool snapshot(double& s,uint64_t& h)const{for(int i=0;i<3;++i){auto a=sequence.load(std::memory_order_acquire);if(a&1)continue;s=sample.load(std::memory_order_relaxed);h=host.load(std::memory_order_relaxed);auto b=sequence.load(std::memory_order_acquire);if(a==b&&a&&h)return true;}return false;}
    void reset(){sequence=0;host=0;sample=0;} // Both audio endpoints stopped.
};
struct CallbackTiming {
    static constexpr size_t bins=256;
    std::atomic<uint64_t> count{0},totalNS{0},maxNS{0};std::array<std::atomic<uint64_t>,bins> histogram{};
    double nanosPerTick=1;
    void prepare(){mach_timebase_info_data_t t{};mach_timebase_info(&t);nanosPerTick=double(t.numer)/t.denom;}
    void record(uint64_t ticks){auto ns=uint64_t(ticks*nanosPerTick);auto us=std::max(uint64_t(1),ns/1000);unsigned power=std::bit_width(us)-1;size_t bin=std::min(size_t(255),size_t(power*8+(us-(uint64_t(1)<<power))*8/(uint64_t(1)<<power)));histogram[bin].fetch_add(1,std::memory_order_relaxed);totalNS.fetch_add(ns,std::memory_order_relaxed);maxNS.store(std::max(maxNS.load(std::memory_order_relaxed),ns),std::memory_order_relaxed);count.fetch_add(1,std::memory_order_relaxed);}
    double percentileUS(double p)const{uint64_t target=uint64_t(std::ceil(count.load()*p)),n=0;if(!target)return 0;for(size_t b=0;b<bins;++b){n+=histogram[b].load();if(n>=target)return std::ldexp(1.,int(b/8))*(1+(b%8+1)/8.);}return 0;}
    void reset(){count=0;totalNS=0;maxNS=0;for(auto& b:histogram)b=0;}
};
struct ClockDescription {
    uint32_t device=0,domain=0,source=0;
    double nominal=0,actual=0;
    std::string uid,clockDevice,details;
};
ClockDescription describeClock(uint32_t device);
bool clockConfigurationMatches(const ClockDescription& before);
// Controller-thread timestamp regression over >=10s windows, never inferred solely from device rate labels.
class ClockEstimator {
    double startSample=0,startTime=0,lastSample=0,lastTime=0;
public:
    double estimatedRate=0;
    bool update(const TimestampMailbox& m,double secondsPerTick){double s;uint64_t h;if(!m.snapshot(s,h))return false;double t=h*secondsPerTick;
        if(!startTime||t<lastTime||s<lastSample){startSample=s;startTime=t;estimatedRate=0;}
        lastTime=t;lastSample=s;if(t-startTime<10)return false;
        double r=(s-startSample)/(t-startTime);startSample=s;startTime=t;
        if(!std::isfinite(r)||r<8000||r>192000){estimatedRate=0;return false;}estimatedRate=estimatedRate?estimatedRate*.8+r*.2:r;return true;}
    void reset(){*this=ClockEstimator{};}
};
