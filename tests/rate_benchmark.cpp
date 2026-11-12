#ifdef USE_BASELINE
#include "../build/parity-baseline/src/AudioBridge.hpp"
#include "../src/ClockRateAdapter.hpp"
#else
#include "../src/AudioBridge.hpp"
#endif
#include <chrono>
#include <cstdio>
#include <vector>
int main(int argc,char** argv){size_t blocks=argc>1?std::stoul(argv[1]):10000;
#ifdef USE_BASELINE
 std::vector<RateMode> modes{RateMode::Legacy};
#else
 std::vector<RateMode> modes{RateMode::Legacy,RateMode::Direct,RateMode::Fixed,RateMode::Async};
#endif
 for(auto mode:modes){
  AudioBridge b;double in=mode==RateMode::Fixed?44100:48000,out=48000;b.captureRate=in;b.muted=false;b.parameters.eqBypass=true;b.parameters.limiterBypass=true;
#ifndef USE_BASELINE
  b.rateAdapter.prepare(in,out,{mode!=RateMode::Async,"Synthetic benchmark fixture"},mode==RateMode::Legacy);
#endif
  std::vector<float> l(4096,.125),r(4096,-.25),ol(256),orr(256);b.push(l.data(),r.data(),2048,1);std::vector<double> us;us.reserve(blocks);double arrival=0;
  for(size_t n=0;n<blocks+100;++n){arrival+=256*in/out;size_t k=size_t(arrival);arrival-=k;b.push(l.data(),r.data(),k,1);auto begin=std::chrono::steady_clock::now();b.render(ol.data(),orr.data(),256,out);auto end=std::chrono::steady_clock::now();if(n>=100)us.push_back(std::chrono::duration<double,std::micro>(end-begin).count());}
  double total=0;for(auto t:us)total+=t;std::sort(us.begin(),us.end());auto p=[&](double f){return us[std::min(us.size()-1,size_t(std::ceil(f*us.size())-1))];};
  printf("%s,%.0f,%.0f,%zu,%.6f,%.6f,%.6f,%.6f,%.6f,%llu,%llu\n",
#ifdef USE_BASELINE
 "Baseline 0.0.15",
#else
 rateModeName(mode),
#endif
 in,out,blocks,total/us.size(),us.back(),p(.95),p(.99),p(.999),(unsigned long long)b.underruns.load(),(unsigned long long)b.overruns.load());
 }
}
