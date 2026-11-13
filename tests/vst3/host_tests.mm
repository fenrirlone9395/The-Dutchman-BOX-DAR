#import <Cocoa/Cocoa.h>
#include "../../src/plugins/VST3Host.hpp"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <new>
#include <thread>
#include <atomic>
#include <chrono>
#include <algorithm>
static thread_local bool watchAllocations=false;
static thread_local size_t allocations=0;
void* operator new(size_t n){if(watchAllocations)++allocations;if(void* p=malloc(n?n:1))return p;throw std::bad_alloc();}
void operator delete(void* p) noexcept {free(p);}
void* operator new[](size_t n){return ::operator new(n);}
void operator delete[](void* p) noexcept {free(p);}
static NSSlider* slider(NSView* v){if([v isKindOfClass:NSSlider.class])return (NSSlider*)v;for(NSView* sub in v.subviews)if(auto* found=slider(sub))return found;return nil;}
int main(int argc,char** argv){if(argc==3&&!strcmp(argv[1],"--vst3-probe"))return runVST3Probe(argv[2]);@autoreleasepool{
    [NSApplication sharedApplication];
    if(argc==2&&(!strcmp(argv[1],"--scan")||!strcmp(argv[1],"--scan-delta"))){std::string report;auto effects=scanVST3Effects(report,!strcmp(argv[1],"--scan"));puts(report.c_str());bool nam=false;for(auto& e:effects){printf("%s | %s\n",e.name.c_str(),e.cid.c_str());if(e.name.find("NeuralAmpModeler")!=std::string::npos)nam=true;}assert(nam);return 0;}
    VST3Choice choice{std::string(getenv("PWD"))+"/build/BOXGain.vst3","424F5854455354310102030405060708","BOX Tests: Deterministic Gain"};
    for(int iteration=0;iteration<8;++iteration){
        if(iteration>=4)setenv("BOX_FIXTURE_SIDECHAIN","1",1);
        VST3Effect effect(choice);if(iteration==7)setenv("BOX_FIXTURE_OPTIONAL_PROCESSING","1",1);assert(effect.prepare(48000)==0);unsetenv("BOX_FIXTURE_OPTIONAL_PROCESSING");float l[512],r[512];
        for(int i=0;i<512;++i){l[i]=4.0f*float(i-255)/256;r[i]=-l[i];}float original[512];memcpy(original,l,sizeof(l));effect.process(l,r,512);assert(!memcmp(l,original,sizeof(l)));assert(l[0]<-1);assert(effect.latency()==0);
        assert(effect.showEditor());NSWindow* editor=nil;for(NSWindow* w in NSApp.windows)if([w.title containsString:@"BOX Tests"])editor=w;assert(editor&&editor.level==NSFloatingWindowLevel);
        NSSlider* control=slider(editor.contentView);assert(control);control.doubleValue=0.25;[control sendAction:control.action to:control.target];
        memcpy(l,original,sizeof(l));effect.process(l,r,512);for(int i=0;i<512;++i)assert(l[i]==original[i]*0.5f);
        CFPropertyListRef state=effect.copyState();assert(state);VST3Effect restored(choice);assert(!restored.prepare(44100));assert(!restored.restore(state));CFRelease(state);memcpy(l,original,sizeof(l));restored.process(l,r,512);for(int i=0;i<512;++i)assert(l[i]==original[i]*0.5f);
        effect.bypass=true;memcpy(l,original,sizeof(l));effect.process(l,r,512);assert(!memcmp(l,original,sizeof(l)));effect.closeEditor();assert(effect.showEditor());effect.closeEditor();
        assert(effect.prepare(96000)==0);
        effect.bypass=false;
        std::array<double,1000> timings{};
        watchAllocations=true;
        for(int i=0;i<1000;++i){memcpy(l,original,sizeof(l));auto start=std::chrono::steady_clock::now();effect.process(l,r,512);timings[i]=std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-start).count();}
        watchAllocations=false;assert(allocations==0);
        if(iteration==0){std::sort(timings.begin(),timings.end());double sum=0;for(auto t:timings)sum+=t;printf("Fixture 96k, 512 frames: mean %.3f us, max %.3f us, p95 %.3f, p99 %.3f, p99.9 %.3f; C++ allocations=%zu\n",sum/timings.size(),timings.back(),timings[949],timings[989],timings[998],allocations);}


    }
    unsetenv("BOX_FIXTURE_SIDECHAIN");
    if(argc>=2){VST3Choice real{argv[1],argc>=3?argv[2]:"F2AEE70D00DE4F4E534441613159456F","Manufacturer test"};VST3Effect effect(real);auto status=effect.prepare(48000);printf("Manufacturer prepare=%d / %s\n",int(status),effect.errorDetail());assert(!status);float l[512]{},r[512]{};double energy=0;for(int block=0;block<100;++block){for(int i=0;i<512;++i){l[i]=0.1f*std::sin((block*512+i)*2*3.141592653589793*440/48000);r[i]=l[i];}effect.process(l,r,512);for(float v:l)energy+=double(v)*v;}assert(!effect.error);printf("Manufacturer processed sine RMS %.8f\n",std::sqrt(energy/(512*100)));assert(energy>1e-6);assert(effect.showEditor());[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];effect.closeEditor();}
    puts("PASS: VST3 stereo Float32 + inactive auxiliary bus layout/pointers, >0 dBFS preserved, native GUI edits change audio, state restore, bypass bit exact, 8 close/reopen/removal cycles, rate re-prepare");
}}
