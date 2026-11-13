#include "../src/AudioBridge.hpp"
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
int main(){
    // Reproduce a frozen block write limit. Do not change that behavior in this investigation.
    {ClockRateAdapter a;a.prepare(48000,48000,{});auto reader=[](int64_t){return std::array<float,2>{.125f,.125f};};uint64_t frozen=2048;float l,r;
     for(int block=0;block<3;++block){a.begin(frozen,512);for(size_t i=0;i<512;++i)a.next(frozen,i,512,reader,l,r);}
     a.begin(frozen,512);uint64_t live=frozen+512;
     bool available=a.next(frozen,0,512,reader,l,r);
     assert(!available && a.telemetry.recoveries==1 && live-a.consumed()>a.requiredInput(a.stepAt(0,512)));
     printf("REPRO frozen write limit: snapshot available=%llu, current available=%llu, needed=%zu; recovery despite newer published input (synthetic scheduling case)\n",(unsigned long long)(frozen-a.consumed()),(unsigned long long)(live-a.consumed()),a.requiredInput(a.stepAt(0,512)));
    }
    // Observe one true source pause, then re-priming and the exact zero-input frame count.
    {AudioBridge b;b.captureRate=48000;b.rateAdapter.prepare(48000,48000,{});b.parameters.eqBypass=true;b.parameters.limiterBypass=true;b.muted=false;
     std::vector<float> source(4096,.125f);float l[512],r[512];b.push(source.data(),source.data(),2048,1);
     for(int i=0;i<6;++i)b.render(l,r,512,48000);
     assert(b.underruns==1&&b.rateAdapter.telemetry.recoveries==1&&b.recoveryZeroInputFrames>0);
     RecoveryEvent event;assert(b.recoveryEvents.pop(event));assert(event.reason==RecoveryReason::InputLookaheadShortage&&event.liveWrite==event.snapshotWrite&&event.zeroInputFrames>0);
     printf("REPRO source pause: event frame=%u/%u, frozen/live=%llu/%llu, first-block zero inputs=%u, cumulative=%llu\n",event.frameInBlock,event.frames,(unsigned long long)(event.snapshotWrite-event.cursor),(unsigned long long)(event.liveWrite-event.cursor),event.zeroInputFrames,(unsigned long long)b.recoveryZeroInputFrames.load());
     b.push(source.data(),source.data(),2048,1);b.render(l,r,512,48000);assert(b.recoveryEvents.pop(event)&&event.reason==RecoveryReason::Reprimed);assert(!b.recoveryEvents.pop(event));
    }
    // Arrival gaps vs sampleTime gaps are different observations.
    {EndpointActivity a;a.nanosPerTick=1;a.observe(1000000000,512,48000,0);a.observe(1032000000,512,48000,512);assert(a.longGaps==1&&a.sampleJumps==0);a.observe(1042666667,512,48000,1536);assert(a.sampleJumps==1&&a.lastSampleGap==512);}
    // Bounded queue never waits or overwrites unread observations.
    {RecoveryEvents q;RecoveryEvent e;for(int i=0;i<128;++i){e.outputBlock=i;assert(q.push(e));}assert(!q.push(e)&&q.dropped==1);for(int i=0;i<128;++i){assert(q.pop(e));assert(e.outputBlock==uint64_t(i));}assert(!q.pop(e));}
    // Controller-only queue-disturbance experiment, not a complete hardware reconstruction.
    // Output pauses/blocked callbacks allow Capture to build up a backlog even without clock drift.
    for(double jump:{0.,512.,1024.,1520.,2048.}){DriftController c;double fill=2048,min=fill,max=fill,ppm=0;constexpr double dt=512./48000;bool hit=false;
      for(int block=0;block<int(900/dt);++block){double seconds=block*dt;if(block==2812)fill+=jump;ppm=c.update(fill,2048,48000,dt,1.2);min=std::min(min,fill);max=std::max(max,fill);
        if(fill<512){printf("REPRO queue burst +%.0f frames: below-512-frame lookahead at %.2fs, entry fill %.2f, correction %+.2fppm, P %+.2f I %+.2f (actual clock +1.2ppm, no capture loss)\n",jump,seconds,fill,ppm,c.diagnosticState()[1],c.diagnosticState()[2]);hit=true;break;}
        fill+=512*(1.2-ppm)*1e-6;
      }
      if(!hit)printf("Queue burst +%.0f: no below-lookahead fill / 15min, fill %.2f..%.2f\n",jump,min,max);
    }
    puts("PASS: starvation/reprime records, zero-input accounting, arrival/sample-time distinction, bounded event queue; SRC/controller unchanged");
}
