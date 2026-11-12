#pragma once
#include <atomic>
#include <array>
#include <algorithm>
#include <cmath>
#include <numbers>

struct DSPParameters {
    std::atomic<float> inputDB{0}, masterDB{0};
    static constexpr std::array<float,15> centers{25,40,63,100,160,250,400,630,1000,1600,2500,4000,6300,10000,16000};
    std::array<std::atomic<float>,15> bands{};
    std::atomic<bool> eqBypass{false}, limiterBypass{false};
};
// Audio-thread-owned state. Parameter transport is atomic, all storage is fixed.
class InternalDSP {
    struct Band { double z1[2]{},z2[2]{},b0=1,b1=0,b2=0,a1=0,a2=0; float gain=0; };
    std::array<Band,15> filters{};
    float input=1,master=1,inputTarget=1,masterTarget=1;
    float wet=1,wetTarget=1;
    float limitGain=1,limitWet=1,limitTarget=1;
    float smooth=0,release=0;
public:
    static constexpr float ceiling=0.891250938f; // -1 dBFS sample peak; not a true-peak limiter.
    float reduction=0;
    void reset() { *this=InternalDSP{}; }
    void begin(const DSPParameters& p,double rate,size_t frames) {
        smooth=1-std::exp(-1.0/(rate*0.010));
        release=std::exp(-1.0/(rate*0.080));
        inputTarget=std::pow(10.f,std::clamp(p.inputDB.load(),-24.f,12.f)/20);
        masterTarget=std::pow(10.f,std::clamp(p.masterDB.load(),-60.f,6.f)/20);
        wetTarget=p.eqBypass?0:1; limitTarget=p.limiterBypass?0:1;
        float blockSmooth=1-std::exp(-double(frames)/(rate*0.025));
        for(size_t i=0;i<filters.size();++i) {
            auto& f=filters[i];
            f.gain+=(std::clamp(p.bands[i].load(),-12.f,12.f)-f.gain)*blockSmooth;
            double hz=std::min(double(DSPParameters::centers[i]),rate*0.45);
            double A=std::pow(10.,f.gain/40.),w=2*std::numbers::pi*hz/rate;
            double alpha=std::sin(w)/(2*2.14),a0=1+alpha/A;
            f.b0=(1+alpha*A)/a0; f.b1=-2*std::cos(w)/a0; f.b2=(1-alpha*A)/a0;
            f.a1=f.b1; f.a2=(1-alpha/A)/a0;
        }
        reduction=0;
    }
    void processInput(float& l,float& r) {
        input+=(inputTarget-input)*smooth;
        l*=input; r*=input;
    }
    void processMaster(float& l,float& r) {
        master+=(masterTarget-master)*smooth;
        wet+=(wetTarget-wet)*smooth; limitWet+=(limitTarget-limitWet)*smooth;
        float x[2]{l,r};
        for(int ch=0;ch<2;++ch) {
            double dry=x[ch],y=dry;
            for(auto& f:filters) {
                double filtered=f.b0*y+f.z1[ch];
                f.z1[ch]=f.b1*y-f.a1*filtered+f.z2[ch]; f.z2[ch]=f.b2*y-f.a2*filtered;
                if(std::abs(f.z1[ch])<1e-25) f.z1[ch]=0;
                if(std::abs(f.z2[ch])<1e-25) f.z2[ch]=0;
                y=filtered;
            }
            x[ch]=(dry+(y-dry)*wet)*master;
        }
        float peak=std::max(std::abs(x[0]),std::abs(x[1]));
        float required=peak>ceiling?ceiling/peak:1;
        limitGain=required<limitGain?required:release*limitGain+(1-release)*required;
        float g=1+(limitGain-1)*limitWet;
        reduction=std::max(reduction,-20*std::log10(std::max(g,1e-12f)));
        l=x[0]*g; r=x[1]*g;
    }
    // Convenience for standalone DSP tests; the engine inserts AU Rack between these stages.
    void process(float& l,float& r) { processInput(l,r); processMaster(l,r); }
};
struct StereoMeter {
    std::atomic<float> peaks[2]{};
    static void maximum(std::atomic<float>& target,float value) {
        float current=target.load(std::memory_order_relaxed);
        while(current<value && !target.compare_exchange_weak(current,value,std::memory_order_relaxed)) {}
    }
    void publish(float l,float r) { maximum(peaks[0],l); maximum(peaks[1],r); }
    void reset() { peaks[0]=0; peaks[1]=0; }
};
