#pragma once
#include <array>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <numbers>
struct SpatialParameters {
    std::atomic<bool> enabled{false};
    std::atomic<float> angle{30},distance{1.5f},amount{0.5f};
};
// Geometric crossfeed, not an HRTF renderer. Audio-thread-owned, fixed storage.
class CrossfeedDSP {
    std::array<std::array<float,2>,2048> delay{};
    size_t cursor=0;
    float lp[2]{},wet=0,mix=0,delayFrames=0,filter=0;
    float wetTarget=0,mixTarget=0,delayTarget=0,filterTarget=0,smooth=0;
public:
    void reset(){*this=CrossfeedDSP{};}
    void begin(const SpatialParameters& p,double rate) {
        double angle=std::clamp(p.angle.load(),10.f,75.f)*std::numbers::pi/180;
        double distance=std::clamp(p.distance.load(),.4f,3.f),ear=.0875;
        double x=distance*std::sin(angle),z=distance*std::cos(angle);
        double near=std::hypot(x-ear,z),far=std::hypot(x+ear,z);
        delayTarget=std::clamp(float((far-near)/343*rate),0.f,2045.f);
        mixTarget=std::clamp(p.amount.load(),0.f,1.f)*.6f*near/far;
        filterTarget=1-std::exp(-2*std::numbers::pi*std::clamp(1800-1400*std::sin(angle),400.,1800.)/rate);
        wetTarget=p.enabled?1:0;smooth=1-std::exp(-1/(rate*.020));
    }
    void process(float& l,float& r) {
        wet+=(wetTarget-wet)*smooth;mix+=(mixTarget-mix)*smooth;
        delayFrames+=(delayTarget-delayFrames)*smooth;filter+=(filterTarget-filter)*smooth;
        lp[0]+=filter*(l-lp[0]);lp[1]+=filter*(r-lp[1]);
        if(std::abs(lp[0])<1e-25)lp[0]=0;if(std::abs(lp[1])<1e-25)lp[1]=0;
        delay[cursor]={lp[0],lp[1]};
        size_t offset=size_t(delayFrames);float fraction=delayFrames-offset;
        auto a=delay[(cursor+delay.size()-offset)%delay.size()];auto b=delay[(cursor+delay.size()-offset-1)%delay.size()];
        float crossL=a[0]+(b[0]-a[0])*fraction,crossR=a[1]+(b[1]-a[1])*fraction;
        float outL=(l+mix*crossR)/(1+mix),outR=(r+mix*crossL)/(1+mix);
        l+=(outL-l)*wet;r+=(outR-r)*wet;cursor=(cursor+1)%delay.size();
    }
};
