#include "../src/DSP.hpp"
#include <cassert>
#include <iostream>
// Steady-state sine response, all control paths exercised at real device rates.
static double response(double rate,float db,float hz,bool bypass=false,size_t band=8) {
    InternalDSP dsp; DSPParameters p; p.bands[band]=db; p.eqBypass=bypass; p.limiterBypass=true;
    double energy=0;
    for(int block=0;block<600;++block) {
        dsp.begin(p,rate,256);
        for(int i=0;i<256;++i) {
            float l=0.01f*std::sin(2*std::numbers::pi*hz*(block*256+i)/rate),r=0;
            dsp.process(l,r); assert(std::isfinite(l)); assert(r==0);
            if(block>=300) energy+=l*l;
        }
    }
    return std::sqrt(energy/(300*256))*std::sqrt(2)/0.01;
}
int main() {
    for(double rate:{44100.,48000.,96000.}) {
        assert(std::abs(response(rate,0,1000)-1)<0.01);
        assert(std::abs(response(rate,6,1000)-std::pow(10,6./20))<0.02);
        assert(std::abs(response(rate,-12,1000)-std::pow(10,-12./20))<0.01);
        assert(std::abs(response(rate,12,1000,true)-1)<0.01);
        for(float hz:{20.f,10000.f,20000.f}) assert(std::isfinite(response(rate,12,hz)));
    }
    for(size_t band=0;band<15;++band) {
        double gain=response(48000,6,DSPParameters::centers[band],false,band);
        assert(std::abs(gain-std::pow(10,6./20))<0.025);
    }
    InternalDSP dsp; DSPParameters p; p.inputDB=12; p.masterDB=6;
    for(int block=0;block<1000;++block) {
        dsp.begin(p,48000,256);
        for(int i=0;i<256;++i) { float l=2,r=-1; dsp.process(l,r); assert(std::abs(l)<=InternalDSP::ceiling+1e-5); assert(std::abs(l+2*r)<1e-5); }
    }
    assert(dsp.reduction>20); // Both channels share one limiter gain.
    p.inputBypass=true; p.masterBypass=true; p.limiterBypass=true;
    float l=0,r=0;
    for(int block=0;block<1000;++block) { dsp.begin(p,48000,256); for(int i=0;i<256;++i) {l=0.5;r=-0.25;dsp.process(l,r);} }
    assert(std::abs(l-0.5)<1e-4 && std::abs(r+0.25)<1e-4);
    // A changing master gain must scale an existing EQ tail after the filters.
    InternalDSP reference,post; DSPParameters unity,attenuated;
    unity.bands[0]=attenuated.bands[0]=12; unity.limiterBypass=attenuated.limiterBypass=true;
    for(int block=0;block<100;++block) { reference.begin(unity,48000,256);post.begin(attenuated,48000,256);for(int i=0;i<256;++i){float a=0,b=0,c=0,d=0;reference.process(a,b);post.process(c,d);} }
    attenuated.masterDB=-12;
    float expectedMaster=1, target=std::pow(10.f,-12.f/20),smoothing=1-std::exp(-1.0/(48000*.01));
    for(int block=0;block<50;++block) {reference.begin(unity,48000,256);post.begin(attenuated,48000,256);for(int i=0;i<256;++i){float a=(block==0&&i==0)?.05f:0,b=0,c=a,d=0;reference.process(a,b);post.process(c,d);expectedMaster+=(target-expectedMaster)*smoothing;assert(std::abs(c-a*expectedMaster)<1e-7);} }
    StereoMeter meter; meter.publish(0.2,1.1); meter.publish(0.1,0.4);
    assert(meter.peaks[0].exchange(0)==0.2f && meter.peaks[1].exchange(0)==1.1f);
    assert(meter.peaks[0]==0);
    std::cout<<"PASS: EQ response/bypass/rates, channel isolation, limiter ceiling/link, gain bypass, stereo meter\n";
}
