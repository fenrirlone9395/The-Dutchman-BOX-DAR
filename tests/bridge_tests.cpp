#include "../src/AudioBridge.hpp"
#include <cassert>
#include <iostream>
#include <limits>
#include <thread>
#include <vector>
struct ProbeRack : BlockProcessor {
    float sentL=0,sentR=0;
    int prepare(double) override { return 0; }
    void process(float* l,float* r,size_t frames) override {
        sentL=l[frames-1];sentR=r[frames-1];
        // Nonlinear effect: gain before this stage cannot be confused with gain after it.
        for(size_t i=0;i<frames;++i) {l[i]=l[i]*l[i]*l[i];r[i]=r[i]*r[i]*r[i];}
    }
};
int main() {
    for(double rate:{44100.,48000.,96000.}) {
        AudioBridge chain; ProbeRack probe; chain.rack=&probe;chain.muted=false;
        chain.parameters.inputDB=-12;chain.parameters.masterDB=-6;chain.parameters.limiterBypass=true;
        std::vector<float> left(4096,.25f),right(4096,-.5f),outL(256),outR(256);
        chain.push(left.data(),right.data(),2048,1);
        double arrival=0;
        auto render=[&]{ arrival+=256*48000/rate;size_t n=size_t(arrival);arrival-=n;chain.push(left.data(),right.data(),n,1);chain.render(outL.data(),outR.data(),256,rate); };
        for(int i=0;i<200;++i)render();
        float input=std::pow(10.f,-12.f/20),master=std::pow(10.f,-6.f/20);
        assert(std::abs(probe.sentL-.25f*input)<1e-5 && std::abs(probe.sentR+.5f*input)<1e-5);
        assert(std::abs(outL.back()-std::pow(.25f*input,3)*master)<1e-6);
        assert(std::abs(outR.back()-std::pow(-.5f*input,3)*master)<1e-6);
        chain.parameters.inputDB=0;
        for(int i=0;i<200;++i)render();
        assert(std::abs(probe.sentL-.25f)<3e-5 && std::abs(probe.sentR+.5f)<3e-5);
        chain.parameters.masterDB=-24;
        for(int i=0;i<200;++i)render();
        assert(std::abs(probe.sentL-.25f)<3e-5); // Master gain must not affect plugin send.
    }
    std::cout<<"PASS: pre-AU input gain, nonlinear effect chain, input unity reset, independent master gain at 44.1/48/96 kHz\n";
    AudioBridge b;
    std::vector<float> l(4096,0.25f),r(4096,-0.5f),ol(512),orr(512);
    b.push(l.data(),r.data(),4096,1);
    b.render(ol.data(),orr.data(),512,48000);
    for(auto x:ol) assert(x==0); // Startup must be silent.
    b.muted=false; b.render(ol.data(),orr.data(),512,48000);
    assert(std::abs(ol.back()-0.25f)<1e-6 && std::abs(orr.back()+0.5f)<1e-6);
    b.reset(); assert(!b.muted); b.push(l.data(),r.data(),4096,1);
    b.muted=true; b.render(ol.data(),orr.data(),512,48000);
    for(auto x:ol) assert(x==0); // Emergency mute is immediate.
    b.reset(); b.push(l.data(),r.data(),40000,1); assert(b.overruns==1 && b.queued()==0);
    l[0]=std::numeric_limits<float>::quiet_NaN(); b.push(l.data(),r.data(),4096,1); assert(b.invalid==1); l[0]=0.25f;
    for(double rate:{44100.,48000.,96000.}) {
        b.reset(); b.muted=false; b.push(l.data(),r.data(),2048,1);
        double arrival=0;
        for(int i=0;i<100000;++i) { // 9–19 simulated minutes, +100 ppm capture clock.
            arrival+=256*48000/rate*1.0001;
            size_t count=size_t(arrival); arrival-=count;
            b.push(l.data(),r.data(),count,1);
            b.render(ol.data(),orr.data(),256,rate);
            assert(b.queued()<8192);
            for(int j=0;j<256;++j) assert(std::isfinite(ol[j]));
        }
        assert(b.underruns==0 && b.overruns==0);
    }
    b.reset(); b.render(ol.data(),orr.data(),512,48000); assert(b.underruns==0);
    b.push(l.data(),r.data(),2048,1);
    for(int i=0;i<10;++i) b.render(ol.data(),orr.data(),512,48000);
    assert(b.underruns==1);
    b.reset();
    std::thread producer([&]{ for(int i=0;i<100000;++i) b.push(l.data(),r.data(),64,1); });
    for(int i=0;i<100000;++i) b.render(ol.data(),orr.data(),64,48000);
    producer.join();
    std::cout<<"PASS: silence, stereo, mute, overflow, invalid samples, SRC/drift, underrun, concurrent stress\n";
}
