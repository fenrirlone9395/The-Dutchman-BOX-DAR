// Offline observation only; uses production engine headers without altering DSP.
#include "../src/AudioBridge.hpp"
#include <bit>
#include <cstdio>
#include <vector>
#include <numbers>
int main(){puts("mode,flat_eq,limiter,signal_peak,max_error,rms_error,bit_mismatches,output_peak,correction_ppm,underruns");
for(int kind=0;kind<4;++kind){AudioBridge b;b.captureRate=44100;ClockEvidence e;e.synchronized=kind!=2;b.rateAdapter.prepare(44100,44100,e);b.parameters.eqBypass=kind==0;b.parameters.limiterBypass=kind!=3;b.muted=false;
constexpr size_t blocks=800,frames=256;std::vector<float> src(blocks*frames+4096);for(size_t i=0;i<src.size();++i){double v=kind==3?.99*sin(2*std::numbers::pi*997*i/44100):.4*sin(2*std::numbers::pi*997*i/44100)+.2*sin(2*std::numbers::pi*18000*i/44100);src[i]=float(std::round(v*32768)/32768);}
b.push(src.data(),src.data(),2048,1);size_t cursor=2048,n=0,mismatch=0;double max=0,sum=0,peak=0,inpeak=0;float l[256],r[256];for(size_t block=0;block<blocks;++block){b.push(src.data()+cursor,src.data()+cursor,frames,1);cursor+=frames;b.render(l,r,frames,44100);if(block>=200)for(size_t i=0;i<frames;++i){float ref=src[block*frames+i];double err=l[i]-ref;max=std::max(max,std::abs(err));sum+=err*err;peak=std::max(peak,std::abs(double(l[i])));inpeak=std::max(inpeak,std::abs(double(ref)));mismatch+=std::bit_cast<uint32_t>(ref)!=std::bit_cast<uint32_t>(l[i]);++n;}}
printf("%s,%d,%d,%.9g,%.9g,%.9g,%zu,%.9g,%.9g,%llu\n",rateModeName(b.rateAdapter.mode()),kind!=0,kind==3,inpeak,max,sqrt(sum/n),mismatch,peak,b.rateAdapter.telemetry.ppm.load(),(unsigned long long)b.underruns.load());}}
