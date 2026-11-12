#ifndef BRIDGE_HEADER
#define BRIDGE_HEADER "../src/AudioBridge.hpp"
#endif
#include BRIDGE_HEADER
#include <cstdio>
#include <random>
#include <vector>
int main(){std::mt19937 random(1234);for(double rate:{44100.,48000.,96000.}){
 AudioBridge b;b.captureRate=48000;b.muted=false;std::vector<float> l(4096),r(4096),ol(256),orr(256);
 auto push=[&](size_t n){for(size_t j=0;j<n;++j){l[j]=float(int(random()%10000)-5000)/1024;r[j]=-l[j]*.7f;}b.push(l.data(),r.data(),n,1);};push(2048);double arrival=0;
 for(int k=0;k<1000;++k){arrival+=256*48000/rate;size_t n=size_t(arrival);arrival-=n;push(n);if(k==50)b.parameters.inputDB=-12;if(k==100)b.parameters.masterDB=-6;if(k==150)b.parameters.bands[8]=6;if(k==250)b.spatialParameters.enabled=true;if(k==400)b.parameters.limiterBypass=true;if(k==500)b.muted=true;if(k==510)b.muted=false;
 b.render(ol.data(),orr.data(),256,rate);fwrite(ol.data(),4,256,stdout);fwrite(orr.data(),4,256,stdout);}
}}
