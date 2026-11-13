#ifndef BRIDGE_HEADER
#define BRIDGE_HEADER "../src/AudioBridge.hpp"
#endif
#include BRIDGE_HEADER
#include <cstdio>
#include <random>
#include <vector>
int main(){for(int mode=0;mode<4;++mode){AudioBridge b;double in=mode==2?44100:48000,out=48000;b.captureRate=in;b.muted=false;b.parameters.limiterBypass=true;b.parameters.eqBypass=true;
 b.rateAdapter.prepare(in,out,{mode==1||mode==2,"Pinned parity fixture"},mode==0);
 std::mt19937 random(42);std::vector<float> l(4096),r(4096),ol(512),orr(512);auto push=[&](size_t n){for(size_t j=0;j<n;++j){l[j]=float(int(random()%10000)-5000)/2048;r[j]=l[j]*.25f;}b.push(l.data(),r.data(),n,1);};push(2048);double arrival=0;
 for(int block=0;block<1100;++block){arrival+=512*in/out;size_t n=size_t(arrival);arrival-=n;if(block<600||block>606)push(n);if(block==200)push(512);if(block==50)b.parameters.inputDB=-6;if(block==250)b.parameters.masterDB=-12;if(block==350)b.parameters.bands[8]=3;if(block==450)b.spatialParameters.enabled=true;if(block==500)b.feedForwardPPM=125;if(block==800)b.muted=true;if(block==805)b.muted=false;
 b.render(ol.data(),orr.data(),512,out);fwrite(ol.data(),4,512,stdout);fwrite(orr.data(),4,512,stdout);}
}}
