#include "../src/AudioBridge.hpp"
#include <cassert>
#include <bit>
#include <cstdio>
#include <random>
#include <vector>
#include <cstdlib>
#include <new>
static bool forbidAllocation=false;
void* operator new(std::size_t n){assert(!forbidAllocation);if(void* p=std::malloc(n?n:1))return p;throw std::bad_alloc();}
void operator delete(void* p) noexcept{std::free(p);}
void* operator new[](std::size_t n){return ::operator new(n);}
void operator delete[](void* p) noexcept{std::free(p);}
int main(){
    assert([]{ClockRateAdapter a;a.prepare(48000,48000,{});return a.mode()==RateMode::Async;}());
    ClockEvidence proven{true,"Synthetic common clock fixture"};

    { ClockRateAdapter a;a.prepare(44100,48000,proven);assert(a.mode()==RateMode::Fixed);a.prepare(44100,48000,{});assert(a.mode()==RateMode::Async);a.prepare(48000,48000,{},true);assert(a.mode()==RateMode::Legacy); }
    { TimestampMailbox m;ClockEstimator estimate;m.publish(0,1000000000);estimate.update(m,1e-9);m.publish(480048,11000000000);assert(estimate.update(m,1e-9));assert(std::abs(estimate.estimatedRate-48004.8)<1e-8); }
    { ClockRateAdapter a;a.prepare(48000,48000,proven);float values[]{-0.f,std::numeric_limits<float>::denorm_min(),-std::numeric_limits<float>::denorm_min(),4.f,std::numeric_limits<float>::max()};auto reader=[&](int64_t n){return std::array<float,2>{values[n%5],values[n%5]};};a.begin(2048,5);for(size_t i=0;i<5;++i){float l,r;assert(a.next(2048,i,5,reader,l,r));assert(std::bit_cast<uint32_t>(l)==std::bit_cast<uint32_t>(values[i]));} }
    for(double rate:{44100.,48000.,96000.}){
        AudioBridge b;b.captureRate=rate;b.rateAdapter.prepare(rate,rate,proven);b.parameters.eqBypass=true;b.parameters.limiterBypass=true;b.muted=false;
        std::vector<float> input(131072),r(131072);std::mt19937 rng(42);for(size_t n=0;n<input.size();++n){input[n]=float(int(rng()%100000)-50000)/8192;r[n]=-input[n];}
        b.push(input.data(),r.data(),2048,1);float l[256],rr[256];double max=0,sum=0;size_t count=0,cursor=2048;
        for(int block=0;block<300;++block){b.push(input.data()+cursor,r.data()+cursor,256,1);cursor+=256;b.render(l,rr,256,rate);if(block>200)for(int j=0;j<256;++j){float ref=input[block*256+j];double e=l[j]-ref;max=std::max(max,std::abs(e));sum+=e*e;++count;assert(std::bit_cast<uint32_t>(l[j])==std::bit_cast<uint32_t>(ref));assert(rr[j]==-ref);}}
        assert(b.underruns==0&&b.overruns==0);printf("Direct %.0f: bit exact, max=%g RMS=%g (%zu samples >0dBFS included)\n",rate,max,sqrt(sum/count),count);
    }
    for(auto rates:{std::array<double,2>{44100,48000},{48000,44100},{88200,96000},{96000,48000}}){
        SincResampler s;s.prepare(rates[0],rates[1]);auto reader=[](int64_t){return std::array<float,2>{4,-4};};
        for(int k=0;k<100;++k){auto x=s.at(2048,k/100.,reader);assert(std::abs(x[0]-4)<2e-6&&std::abs(x[1]+4)<2e-6);}
        printf("Sinc %.0f->%.0f: unity/headroom/LR, %zu taps\n",rates[0],rates[1],s.taps());
    }
    for(bool timestamps:{false,true})for(double ppm:{-100.,-50.,-10.,10.,50.,100.}){
        DriftController c;double fill=2048,min=fill,max=fill,last=0;const double dt=256./48000; // Simulated one hour. No expensive FIR needed for control-only stability.
        for(int k=0;k<int(3600/dt);++k){double correction=c.update(fill,2048,48000,dt,timestamps&&k*dt>=10?ppm:0);assert(std::abs(correction-last)<=10*dt+1e-8);fill+=256*(ppm-correction)*1e-6;min=std::min(min,fill);max=std::max(max,fill);last=correction;}
        assert(min>1500&&max<2600);assert(std::abs(last-ppm)<.1);printf("Drift %+g ppm / 1h (timestamp feedforward=%d): fill %.2f..%.2f correction %.5f ppm\n",ppm,timestamps,min,max,last);
    }
    for(double ppm:{-100.,-50.,-10.,10.,50.,100.}){
        AudioBridge b;b.captureRate=48000;b.rateAdapter.prepare(48000,48000,{});b.parameters.eqBypass=true;b.parameters.limiterBypass=true;b.muted=false;
        std::vector<float> input(4096,.125f);float l[256],r[256];b.push(input.data(),input.data(),2048,1);double arrived=0;int64_t sent=0;
        for(int block=0;block<1500;++block){arrived+=256*(1+ppm*1e-6);int64_t end=int64_t(arrived)+(block%16<8?48:-48);size_t n=size_t(end-sent);sent=end;b.push(input.data(),input.data(),n,1);
            forbidAllocation=true;b.render(l,r,256,48000);forbidAllocation=false;
            if(block>100)for(float x:l)assert(std::abs(x-.125f)<2e-6);
        }
        assert(!b.underruns&&!b.overruns);printf("Full Float32 ring + ASRC %+g ppm + arrival jitter / 8s: no C++ heap allocation, no discontinuity on DC, no under/overrun; fill %.2f..%.2f\n",ppm,b.rateAdapter.telemetry.minFill.load(),b.rateAdapter.telemetry.maxFill.load());
    }

}
