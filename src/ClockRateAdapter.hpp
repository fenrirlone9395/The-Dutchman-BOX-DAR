#pragma once
#include "SincResampler.hpp"
#include <atomic>
#include <cstdint>
#include <string>

enum class RateMode { Legacy, Direct, Fixed, Async };
inline const char* rateModeName(RateMode m){switch(m){case RateMode::Legacy:return "Legacy Linear";case RateMode::Direct:return "Direct / No SRC";case RateMode::Fixed:return "Fixed Sinc";case RateMode::Async:return "Async Sinc";}return "Unknown";}
struct ClockEvidence {
    bool synchronized=false; // Must be proven including aggregate/tap path, not inferred from equal rate/domain alone.
    std::string reason="Capture clock relationship unknown";
};
struct RateTelemetry {
    std::atomic<double> ratio{1},ppm{0},fill{0},minFill{1e30},maxFill{0},latencyMS{0};
    std::atomic<uint64_t> recoveries{0};
    std::atomic<double> activeMinFill{1e30},filteredFill{0},proportionalPPM{0},integralPPM{0},desiredPPM{0},feedForwardPPM{0};
};
// Output-thread-owned controller, prepared/reset only while output stopped.
class DriftController {
    double filtered=0,integral=0,current=0;
    bool first=true;
    double diagnosticError=0,diagnosticDesired=0;
public:
    void reset(){filtered=integral=current=0;first=true;diagnosticError=diagnosticDesired=0;}
    double update(double fill,double target,double inputRate,double dt,double feedForwardPPM=0){
        if(first){filtered=fill;first=false;}
        filtered+=(fill-filtered)*(-std::expm1(-dt/2));
        double error=(filtered-target)/inputRate; // seconds of queue error
        // 50ppm per ms proportional; integral 2ppm per ms per second.
        integral=std::clamp(integral+error*2000*dt,-1000.,1000.);
        double desired=std::clamp(feedForwardPPM+error*50000+integral,-1000.,1000.);
        diagnosticError=error;diagnosticDesired=desired;
        double delta=10*dt; // max 10ppm/s
        current+=std::clamp(desired-current,-delta,delta);
        return current;
    }
    std::array<double,4> diagnosticState()const{return {filtered,diagnosticError*50000,integral,diagnosticDesired};}
};
class ClockRateAdapter {
    SincResampler sinc;
    DriftController controller;
    uint64_t cursor=0;
    double phase=0,ratioStart=1,ratioEnd=1,inRate=48000,outRate=48000;
    bool primed=false;
    RateMode selected=RateMode::Legacy;
    size_t target=2048;
public:
    RateTelemetry telemetry;
    std::string reason="Legacy compatibility default"; // Control-thread only.
    void prepare(double inputRate,double outputRate,const ClockEvidence& evidence,bool legacy=false){
        if(!std::isfinite(inputRate)||!std::isfinite(outputRate)||inputRate<8000||outputRate<8000||outputRate>192000)throw std::invalid_argument("Invalid adapter rate");
        inRate=inputRate;outRate=outputRate;
        selected=legacy?RateMode::Legacy:evidence.synchronized?(inputRate==outputRate?RateMode::Direct:RateMode::Fixed):RateMode::Async;
        reason=legacy?"Explicit Legacy selection":evidence.reason;
        if(selected==RateMode::Async||selected==RateMode::Fixed)sinc.prepare(inputRate,outputRate);
        target=std::max(size_t(2048),lookahead()+size_t(512*inputRate/outputRate)+32);
        reset();
        telemetry.latencyMS=selected==RateMode::Direct||selected==RateMode::Legacy?0:lookahead()*1000/inputRate;
    }
    void reset(){cursor=0;phase=0;primed=false;ratioStart=ratioEnd=inRate/outRate;controller.reset();telemetry.ratio=ratioEnd;telemetry.ppm=0;telemetry.fill=0;telemetry.minFill=1e30;telemetry.maxFill=0;telemetry.recoveries=0;telemetry.activeMinFill=1e30;telemetry.filteredFill=0;telemetry.proportionalPPM=0;telemetry.integralPPM=0;telemetry.desiredPPM=0;telemetry.feedForwardPPM=0;}
    RateMode mode()const{return selected;}
    size_t lookahead()const{return selected==RateMode::Async||selected==RateMode::Fixed?sinc.lookahead():0;}
    size_t taps()const{return selected==RateMode::Async||selected==RateMode::Fixed?sinc.taps():0;}
    size_t targetFill()const{return target;}
    uint64_t consumed()const{return cursor;}
    double fractionalPosition()const{return phase;}
    bool isPrimed()const{return primed;}
    double stepAt(size_t frame,size_t frames)const{return ratioStart+(ratioEnd-ratioStart)*(frame+1)/frames;}
    size_t requiredInput(double step)const{return selected==RateMode::Direct?1:lookahead()+size_t(std::ceil(step))+2;}
    uint64_t retainedRead()const{return cursor>lookahead()?cursor-lookahead():0;}
    void begin(uint64_t written,size_t frames,double feedForwardPPM=0){
        double fill=double(written-cursor)-phase;
        telemetry.fill=fill;telemetry.minFill=std::min(telemetry.minFill.load(std::memory_order_relaxed),fill);telemetry.maxFill=std::max(telemetry.maxFill.load(std::memory_order_relaxed),fill);
        if(written-cursor>std::max(uint64_t(8192),uint64_t(target*4))){cursor=written-target;phase=0;primed=false;++telemetry.recoveries;}
        if(!primed && written-cursor>=std::max(target,lookahead()+size_t(std::ceil(frames*inRate/outRate*1.001))+2))primed=true;
        if(primed)telemetry.activeMinFill=std::min(telemetry.activeMinFill.load(std::memory_order_relaxed),fill);
        ratioStart=ratioEnd;
        double ppm=selected==RateMode::Async && primed?controller.update(fill,target,inRate,frames/outRate,feedForwardPPM):0;
        ratioEnd=inRate/outRate*(1+ppm*1e-6);telemetry.ppm=ppm;telemetry.ratio=ratioEnd;
        auto state=controller.diagnosticState();telemetry.filteredFill=state[0];telemetry.proportionalPPM=state[1];telemetry.integralPPM=state[2];telemetry.desiredPPM=state[3];telemetry.feedForwardPPM=feedForwardPPM;
    }
    template<class Reader> bool next(uint64_t written,size_t frame,size_t frames,const Reader& reader,float& l,float& r){
        l=r=0;if(!primed)return false;
        double step=ratioStart+(ratioEnd-ratioStart)*(frame+1)/frames;
        if(written-cursor<(selected==RateMode::Direct?1:lookahead()+size_t(std::ceil(step))+2)){primed=false;++telemetry.recoveries;return false;}
        if(selected==RateMode::Direct){auto s=reader(int64_t(cursor));l=s[0];r=s[1];++cursor;return true;}
        auto s=sinc.at(cursor,phase,reader);l=s[0];r=s[1];
        phase+=step;auto used=uint64_t(phase);cursor+=used;phase-=used;return true;
    }
};
