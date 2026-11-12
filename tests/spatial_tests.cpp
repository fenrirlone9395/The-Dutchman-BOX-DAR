#include "../src/SpatialDSP.hpp"
#include "../src/AudioBridge.hpp"
#include <cassert>
#include <iostream>
#include <limits>
static double crossEnergy(double rate,double hz) {
    SpatialParameters p;p.enabled=true;p.amount=1;CrossfeedDSP dsp;dsp.begin(p,rate);double energy=0;
    for(int i=0;i<int(rate);++i){float l=.2*std::sin(2*std::numbers::pi*hz*i/rate),r=0;dsp.process(l,r);if(i>rate/2)energy+=r*r;}
    return energy;
}
int main(){
    for(double rate:{44100.,48000.,96000.,192000.}) {
        SpatialParameters p;CrossfeedDSP dsp;dsp.begin(p,rate);
        for(int i=0;i<1000;++i){float l=.3,r=-.1;dsp.process(l,r);assert(l==.3f&&r==-.1f);} // Off is transparent.
        dsp.reset();p.enabled=true;p.amount=1;dsp.begin(p,rate);
        for(int i=0;i<int(rate/2);++i){float l=0,r=0;dsp.process(l,r);}
        int onset=-1;float maximum=0;
        for(int i=0;i<1024;++i){float l=i==0?1:0,r=0;dsp.process(l,r);if(r>1e-7&&onset<0)onset=i;maximum=std::max(maximum,r);assert(std::isfinite(l)&&std::isfinite(r));}
        assert(onset>1 && maximum>0 && maximum<.5);
        assert(crossEnergy(rate,100)>crossEnergy(rate,8000)*10); // Frequency-dependent head shadow approximation.
        dsp.reset();dsp.begin(p,rate);
        for(int i=0;i<int(rate);++i){float l=.3,r=.3;dsp.process(l,r);if(i>rate*.9){assert(std::abs(l-.3)<1e-4&&std::abs(r-.3)<1e-4);}}
        for(int block=0;block<1000;++block){p.angle=block%2?10:75;p.distance=block%2?.4:3;p.amount=block%3?1:0;p.enabled=block%4!=0;dsp.begin(p,rate);for(int i=0;i<128;++i){float l=.3,r=-.3;dsp.process(l,r);assert(std::isfinite(l)&&std::isfinite(r)&&std::abs(l)<=.3001&&std::abs(r)<=.3001);}}
    }
    struct RightOnlyRack : BlockProcessor {int prepare(double)override{return 0;}void process(float* l,float* r,size_t n)override{for(size_t i=0;i<n;++i){l[i]=0;r[i]=.2f;}}} rack;
    AudioBridge bridge;bridge.rack=&rack;bridge.muted=false;bridge.spatialParameters.enabled=true;
    std::array<float,4096> silence{};std::array<float,256> left{},right{};bridge.push(silence.data(),silence.data(),2048,1);
    for(int i=0;i<200;++i){bridge.push(silence.data(),silence.data(),256,1);bridge.render(left.data(),right.data(),256,48000);}
    assert(left.back()>.01 && right.back()>.1); // Spatial receives the AU output, not capture input.
    std::cout<<"PASS: crossfeed bypass, delayed opposite ear, low-pass dependency, mono/DC preservation, bounded automation, post-AU engine integration at 44.1/48/96/192 kHz\n";
}
