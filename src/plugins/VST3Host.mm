#include "VST3Host.hpp"
#include "VST3Catalog.hpp"
#import <Cocoa/Cocoa.h>
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstmessage.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/connectionproxy.h"
#include "public.sdk/source/common/memorystream.h"
#include <algorithm>
#include <map>
#include <cstring>
#include <signal.h>
using namespace Steinberg;
using namespace Steinberg::Vst;
namespace {
thread_local bool inVSTProcess=false;
struct BOXHost final : HostApplication {
    tresult PLUGIN_API createInstance(TUID cid,TUID iid,void** obj) override {if(inVSTProcess){*obj=nullptr;return kNotImplemented;}return HostApplication::createInstance(cid,iid,obj);}
    tresult PLUGIN_API getName(String128 name) override {const char16_t text[]=u"The Dutchman BOX/DAR";std::fill_n(name,128,0);std::copy(std::begin(text),std::end(text),name);return kResultOk;}
};
BOXHost& hostContext(){static BOXHost host;return host;}
template<class T> T* query(FUnknown* p) { T* r=nullptr;if(p)p->queryInterface(T::iid,(void**)&r);return r; }
template<class T> void drop(T*& p) { if(p){p->release();p=nullptr;} }
// All object lifetimes and module entry/exit operations are confined to the main thread.
struct Module {
    CFBundleRef bundle=nullptr; IPluginFactory* factory=nullptr; bool entered=false;
    bool (*exit)()=nullptr;
    explicit Module(const std::string& path) {
        NSURL* url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
        bundle=CFBundleCreate(nullptr,(__bridge CFURLRef)url);
        if(!bundle || !CFBundleLoadExecutable(bundle))return;
        auto entry=(bool(*)(CFBundleRef))CFBundleGetFunctionPointerForName(bundle,CFSTR("bundleEntry"));
        exit=(bool(*)())CFBundleGetFunctionPointerForName(bundle,CFSTR("bundleExit"));
        auto get=(IPluginFactory*(*)())CFBundleGetFunctionPointerForName(bundle,CFSTR("GetPluginFactory"));
        if(!entry||!exit||!get||!entry(bundle))return;
        entered=true;factory=get();
    }
    ~Module(){drop(factory);if(entered)exit();if(bundle)CFRelease(bundle);}
};
std::shared_ptr<Module> module(const std::string& path) {
    static std::map<std::string,std::weak_ptr<Module>> modules;
    auto m=modules[path].lock();if(!m){m=std::make_shared<Module>(path);modules[path]=m;}return m;
}
std::string hexID(const char* id) { char text[33];for(int i=0;i<16;++i)snprintf(text+2*i,3,"%02X",(unsigned char)id[i]);return text; }
bool parseID(const std::string& text,TUID id) {
    if(text.size()!=32)return false;for(int i=0;i<16;++i){unsigned v;char pair[3]{text[2*i],text[2*i+1],0};if(strspn(pair,"0123456789abcdefABCDEF")!=2||sscanf(pair,"%x",&v)!=1)return false;id[i]=char(v);}return true;
}
// Fixed-capacity queues: no vector growth or SDK ParameterChanges allocation in process().
#define FIXED_UNKNOWN(IFACE) \
    uint32 PLUGIN_API addRef() override{return 1;} uint32 PLUGIN_API release() override{return 1;} \
    tresult PLUGIN_API queryInterface(const TUID id,void** obj) override { \
        if(FUnknownPrivate::iidEqual(id,IFACE::iid)||FUnknownPrivate::iidEqual(id,FUnknown::iid)){*obj=static_cast<IFACE*>(this);return kResultOk;}*obj=nullptr;return kNoInterface; }
struct Queue : IParamValueQueue {
    ParamID id=0;ParamValue value=0;bool used=false;
    FIXED_UNKNOWN(IParamValueQueue)
    ParamID PLUGIN_API getParameterId() override{return id;}
    int32 PLUGIN_API getPointCount() override{return used?1:0;}
    tresult PLUGIN_API getPoint(int32 i,int32& offset,ParamValue& v) override{if(i||!used)return kInvalidArgument;offset=0;v=value;return kResultOk;}
    tresult PLUGIN_API addPoint(int32,ParamValue v,int32& i) override{value=v;used=true;i=0;return kResultOk;}
};
struct Changes : IParameterChanges {
    std::array<Queue,512> queues;int32 count=0;
    FIXED_UNKNOWN(IParameterChanges)
    int32 PLUGIN_API getParameterCount() override{return count;}
    IParamValueQueue* PLUGIN_API getParameterData(int32 i) override{return i>=0&&i<count?&queues[i]:nullptr;}
    IParamValueQueue* PLUGIN_API addParameterData(const ParamID& id,int32& index) override{
        for(int i=0;i<count;++i)if(queues[i].id==id){index=i;return &queues[i];}
        if(count==int(queues.size()))return nullptr;index=count++;auto& q=queues[index];q.id=id;q.used=false;return &q;
    }
    bool set(ParamID id,ParamValue v){int32 i;if(auto* q=addParameterData(id,i)){q->addPoint(0,v,i);return true;}return false;}
};
struct Edit {ParamID id;ParamValue value;};
struct Transfer {
    static constexpr size_t capacity=2048;
    std::array<Edit,capacity> data;std::atomic<size_t> read{0},write{0};
    bool push(Edit e){auto w=write.load(std::memory_order_relaxed);auto n=(w+1)%capacity;if(n==read.load(std::memory_order_acquire))return false;data[w]=e;write.store(n,std::memory_order_release);return true;}
    bool pop(Edit& e){auto r=read.load(std::memory_order_relaxed);if(r==write.load(std::memory_order_acquire))return false;e=data[r];read.store((r+1)%capacity,std::memory_order_release);return true;}
};
}
struct VST3Effect::Impl final : IComponentHandler, IPlugFrame {
    VST3Effect& owner;std::shared_ptr<Module> module;
    IComponent* component=nullptr;IAudioProcessor* processor=nullptr;IEditController* controller=nullptr;
    ConnectionProxy *componentProxy=nullptr,*controllerProxy=nullptr;IPlugView* view=nullptr;
    bool initialized=false,controllerInitialized=false,active=false,processing=false;
    NSPanel* panel=nil;NSView* parent=nil;NSScrollView* scroll=nil;
    std::string stage="not initialized";
    double rate=48000;int64 sampleTime=0;std::atomic<uint32> latencyFrames{0};
    std::atomic<int32> restart{0};Transfer toAudio,toUI;Changes inputChanges,outputChanges;
    static constexpr int maximumBuses=8,maximumChannels=64;
    int32 inputCount=0,outputCount=0;
    std::array<AudioBusBuffers,maximumBuses> inputBuses{},outputBuses{};
    std::array<std::array<float*,maximumChannels>,maximumBuses> inputPointers{},outputPointers{};
    std::array<float,4096> inL{},inR{},outL{},outR{};
    explicit Impl(VST3Effect& o):owner(o){}
    uint32 PLUGIN_API addRef() override{return 1;}uint32 PLUGIN_API release() override{return 1;}
    tresult PLUGIN_API queryInterface(const TUID id,void** obj) override {
        if(FUnknownPrivate::iidEqual(id,IComponentHandler::iid)||FUnknownPrivate::iidEqual(id,FUnknown::iid))*obj=static_cast<IComponentHandler*>(this);
        else if(FUnknownPrivate::iidEqual(id,IPlugFrame::iid))*obj=static_cast<IPlugFrame*>(this);else{*obj=nullptr;return kNoInterface;}return kResultOk;
    }
    tresult PLUGIN_API beginEdit(ParamID) override{return kResultOk;}
    tresult PLUGIN_API performEdit(ParamID id,ParamValue value) override {
        if(!std::isfinite(value)||value<0||value>1)return kInvalidArgument;
        if(!toAudio.push({id,value})){owner.error=kAudio_ParamError;return kOutOfMemory;}return kResultOk;
    }
    tresult PLUGIN_API endEdit(ParamID) override{return kResultOk;}
    tresult PLUGIN_API restartComponent(int32 flags) override {restart.fetch_or(flags);return kResultOk;}
    tresult PLUGIN_API resizeView(IPlugView* v,ViewRect* rect) override {
        if(v!=view||!rect||![NSThread isMainThread])return kInvalidArgument;
        int w=rect->getWidth(),h=rect->getHeight();if(w<100||h<60||w>8192||h>8192)return kInvalidArgument;
        fitEditor(w,h);return view->onSize(rect);
    }
    void fitEditor(int w,int h){
        parent.frame=NSMakeRect(0,0,w,h);
        NSRect screen=(panel.screen?:NSScreen.mainScreen).visibleFrame;
        [panel setContentSize:NSMakeSize(MIN(w,MAX(100,screen.size.width-40)),MIN(h,MAX(60,screen.size.height-80)))];
        [parent scrollPoint:NSMakePoint(0,MAX(0,h-scroll.contentSize.height))];
    }
    void closeEditor(){if(view){view->removed();view->setFrame(nullptr);drop(view);}[panel close];panel.contentView=nil;panel=nil;parent=nil;scroll=nil;}
    void stop(){if(processing){processor->setProcessing(false);processing=false;}if(active){component->setActive(false);active=false;}}
    ~Impl(){closeEditor();stop();if(componentProxy)componentProxy->disconnect();if(controllerProxy)controllerProxy->disconnect();drop(componentProxy);drop(controllerProxy);if(controller)controller->setComponentHandler(nullptr);drop(processor);if(controllerInitialized)controller->terminate();drop(controller);if(initialized)component->terminate();drop(component);}
    bool open(const VST3Choice& choice){
        stage="module load";module=::module(choice.path);if(!module->factory)return false;
        if(auto* factory3=query<IPluginFactory3>(module->factory)){factory3->setHostContext(&hostContext());drop(factory3);}
        TUID id;if(!parseID(choice.cid,id))return false;
        stage="factory.createInstance(IComponent)";if(module->factory->createInstance(id,IComponent::iid,(void**)&component)!=kResultOk||!component)return false;
        stage="component.initialize";if(component->initialize(&hostContext())!=kResultOk)return false;initialized=true;
        stage="query IAudioProcessor";processor=query<IAudioProcessor>(component);if(!processor)return false;
        controller=query<IEditController>(component);
        if(!controller){TUID cid;if(component->getControllerClassId(cid)==kResultOk&&module->factory->createInstance(cid,IEditController::iid,(void**)&controller)==kResultOk&&controller){stage="controller.initialize";if(controller->initialize(&hostContext())!=kResultOk)return false;controllerInitialized=true;}}
        if(controller){controller->setComponentHandler(this);if(controllerInitialized){auto* cp=query<IConnectionPoint>(component);auto* ep=query<IConnectionPoint>(controller);if(cp&&ep){componentProxy=new ConnectionProxy(cp);controllerProxy=new ConnectionProxy(ep);componentProxy->connect(ep);controllerProxy->connect(cp);}drop(cp);drop(ep);}
            MemoryStream state;if(component->getState(&state)==kResultOk){state.seek(0,IBStream::kIBSeekSet,nullptr);controller->setComponentState(&state);}}
        return true;
    }
};
VST3Effect::VST3Effect(VST3Choice c):RackEffect(AUChoice{{},c.name.starts_with("[VST3] ")?c.name:"[VST3] "+c.name}),impl(std::make_unique<Impl>(*this)),vst(std::move(c)){}
VST3Effect::~VST3Effect()=default;
OSStatus VST3Effect::prepare(double rate){
    auto& p=*impl;error=0;p.stop();p.sampleTime=0;
    if(!std::isfinite(rate)||rate<8000||rate>384000)return error=kAudio_ParamError;
    if(!p.component&&!p.open(vst))return error=kAudioUnitErr_FailedInitialization;
    p.stage="processor.canProcessSampleSize(Float32)";if(p.processor->canProcessSampleSize(kSample32)!=kResultTrue)return error=kAudioUnitErr_FormatNotSupported;
    p.stage="component.getBusCount";
    p.inputCount=p.component->getBusCount(kAudio,kInput);p.outputCount=p.component->getBusCount(kAudio,kOutput);
    if(p.inputCount<1||p.outputCount<1||p.inputCount>Impl::maximumBuses||p.outputCount>Impl::maximumBuses)return error=kAudioUnitErr_FormatNotSupported;
    std::array<SpeakerArrangement,Impl::maximumBuses> inputs{},outputs{};
    for(auto direction:{kInput,kOutput}){
        int32 count=direction==kInput?p.inputCount:p.outputCount;
        auto& arrangements=direction==kInput?inputs:outputs;
        for(int32 b=0;b<count;++b){
            p.stage=std::string(direction==kInput?"input":"output")+" bus "+std::to_string(b)+" arrangement";
            if(p.processor->getBusArrangement(direction,b,arrangements[b])!=kResultOk)return error=kAudioUnitErr_FormatNotSupported;
        }
        arrangements[0]=SpeakerArr::kStereo;
    }
    // Preserve declared auxiliary layouts while requesting stereo on the main buses.
    p.stage="processor.setBusArrangements(main stereo, auxiliary layouts preserved)";
    if(p.processor->setBusArrangements(inputs.data(),p.inputCount,outputs.data(),p.outputCount)!=kResultOk)return error=kAudioUnitErr_FormatNotSupported;
    for(auto direction:{kInput,kOutput}){
        int32 count=direction==kInput?p.inputCount:p.outputCount;
        auto& buses=direction==kInput?p.inputBuses:p.outputBuses;
        auto& pointers=direction==kInput?p.inputPointers:p.outputPointers;
        p.stage="audio bus count changed during negotiation";
        if(p.component->getBusCount(kAudio,direction)!=count)return error=kAudioUnitErr_FormatNotSupported;
        for(int32 b=0;b<count;++b){
            std::string bus=std::string(direction==kInput?"input":"output")+" bus "+std::to_string(b);
            p.stage=bus+" layout validation";BusInfo info{};SpeakerArrangement arrangement=0;
            if(p.component->getBusInfo(kAudio,direction,b,info)!=kResultOk||p.processor->getBusArrangement(direction,b,arrangement)!=kResultOk)return error=kAudioUnitErr_FormatNotSupported;
            int channels=SpeakerArr::getChannelCount(arrangement);
            if(channels<0||channels>Impl::maximumChannels||info.channelCount!=channels)return error=kAudioUnitErr_FormatNotSupported;
            if(b==0?(info.busType!=kMain||arrangement!=SpeakerArr::kStereo):info.busType!=kAux)return error=kAudioUnitErr_FormatNotSupported;
            p.stage=bus+(b==0?" activate main":" deactivate auxiliary");
            if(p.component->activateBus(kAudio,direction,b,b==0)!=kResultOk)return error=kAudioUnitErr_FormatNotSupported;
            pointers[b].fill(nullptr);buses[b].numChannels=channels;buses[b].channelBuffers32=pointers[b].data();buses[b].silenceFlags=0;
        }
        for(int32 b=0;b<p.component->getBusCount(kEvent,direction);++b)p.component->activateBus(kEvent,direction,b,false);
    }
    p.inputPointers[0][0]=p.inL.data();p.inputPointers[0][1]=p.inR.data();
    p.outputPointers[0][0]=p.outL.data();p.outputPointers[0][1]=p.outR.data();
    ProcessSetup setup{kRealtime,kSample32,4096,rate};
    p.stage="processor.setupProcessing";if(p.processor->setupProcessing(setup)!=kResultOk)return error=kAudioUnitErr_FailedInitialization;
    p.stage="component.setActive";if(p.component->setActive(true)!=kResultOk)return error=kAudioUnitErr_FailedInitialization;p.active=true;
    p.stage="processor.setProcessing";
    // SDK audiohost tolerates older processors with a no-op/optional setProcessing.
    // setupProcessing/setActive must succeed; process() failures still latch dry/error.
    auto processingResult=p.processor->setProcessing(true);
    if(processingResult!=kResultOk&&processingResult!=kNotImplemented&&processingResult!=kResultFalse){p.stop();return error=kAudioUnitErr_FailedInitialization;}
    p.processing=true;p.rate=rate;p.latencyFrames=p.processor->getLatencySamples();p.restart=0;p.stage="processor.process";return 0;
}
void VST3Effect::process(float* l,float* r,UInt32 frames){
    auto& p=*impl;if(bypass||error||!p.processing||(p.restart.load()&(kIoChanged|kReloadComponent))){p.sampleTime+=frames;return;}
    if(frames>4096){error=kAudioUnitErr_TooManyFramesToProcess;return;}
    memcpy(p.inL.data(),l,frames*4);memcpy(p.inR.data(),r,frames*4);std::fill_n(p.outL.data(),frames,0);std::fill_n(p.outR.data(),frames,0);
    p.inputChanges.count=0;p.outputChanges.count=0;Edit e;for(size_t i=0;i<Transfer::capacity&&p.toAudio.pop(e);++i)if(!p.inputChanges.set(e.id,e.value)){error=kAudio_ParamError;return;}
    for(int32 b=0;b<p.inputCount;++b)p.inputBuses[b].silenceFlags=0;
    for(int32 b=0;b<p.outputCount;++b)p.outputBuses[b].silenceFlags=0;
    auto& output=p.outputBuses[0];
    ProcessContext context{};context.sampleRate=p.rate;context.projectTimeSamples=p.sampleTime;context.continousTimeSamples=p.sampleTime;context.state=ProcessContext::kPlaying|ProcessContext::kContTimeValid;
    ProcessData data{};data.processMode=kRealtime;data.symbolicSampleSize=kSample32;data.numSamples=frames;data.numInputs=p.inputCount;data.numOutputs=p.outputCount;data.inputs=p.inputBuses.data();data.outputs=p.outputBuses.data();data.inputParameterChanges=&p.inputChanges;data.outputParameterChanges=&p.outputChanges;data.processContext=&context;
    inVSTProcess=true;auto result=p.processor->process(data);inVSTProcess=false;p.sampleTime+=frames;
    if(result!=kResultOk){error=kAudioUnitErr_CannotDoInCurrentContext;return;}
    for(int q=0;q<p.outputChanges.count;++q){auto& v=p.outputChanges.queues[q];if(v.used)p.toUI.push({v.id,v.value});}
    for(UInt32 i=0;i<frames;++i)if(!std::isfinite(p.outL[i])||!std::isfinite(p.outR[i])){error=kAudio_ParamError;return;}
    if(output.silenceFlags&1)std::fill_n(l,frames,0);else memcpy(l,p.outL.data(),frames*4);
    if(output.silenceFlags&2)std::fill_n(r,frames,0);else memcpy(r,p.outR.data(),frames*4);
}
const char* VST3Effect::errorDetail() const{return impl->stage.c_str();}
double VST3Effect::latency() const{return impl->latencyFrames.load()/impl->rate;}
bool VST3Effect::showEditor(){
    auto& p=*impl;if(p.panel){[p.panel makeKeyAndOrderFront:nil];return true;}if(!p.controller)return false;
    p.view=p.controller->createView(ViewType::kEditor);if(!p.view)return false;
    if(p.view->isPlatformTypeSupported(kPlatformTypeNSView)!=kResultTrue){drop(p.view);return false;}
    ViewRect rect{};if(p.view->getSize(&rect)!=kResultOk||rect.getWidth()<100||rect.getHeight()<60||rect.getWidth()>8192||rect.getHeight()>8192){drop(p.view);return false;}
    p.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,rect.getWidth(),rect.getHeight()) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];p.panel.releasedWhenClosed=NO;p.panel.floatingPanel=YES;p.panel.level=NSFloatingWindowLevel;p.panel.hidesOnDeactivate=YES;p.panel.title=[NSString stringWithUTF8String:choice.name.c_str()];p.parent=[[NSView alloc] initWithFrame:NSMakeRect(0,0,rect.getWidth(),rect.getHeight())];p.scroll=[[NSScrollView alloc] initWithFrame:p.parent.frame];p.scroll.hasVerticalScroller=YES;p.scroll.hasHorizontalScroller=YES;p.scroll.autohidesScrollers=YES;p.scroll.documentView=p.parent;p.panel.contentView=p.scroll;p.fitEditor(rect.getWidth(),rect.getHeight());
    p.view->setFrame(&p);if(p.view->attached((__bridge void*)p.parent,kPlatformTypeNSView)!=kResultOk){p.closeEditor();return false;}p.view->onSize(&rect);[p.panel center];[p.panel makeKeyAndOrderFront:nil];return true;
}
void VST3Effect::closeEditor(){impl->closeEditor();}
void VST3Effect::idle(){auto& p=*impl;Edit e;while(p.toUI.pop(e))if(p.controller)p.controller->setParamNormalized(e.id,e.value);
    int32 flags=p.restart.exchange(0);if(flags&kLatencyChanged)p.latencyFrames=p.processor->getLatencySamples();
    // IO/layout reload requests require a stopped re-prepare; never rebuild from an audio callback.
    if(flags&(kIoChanged|kReloadComponent))error=kAudioUnitErr_FormatNotSupported;
    if((flags&kParamValuesChanged)&&p.controller)for(int32 i=0;i<p.controller->getParameterCount();++i){ParameterInfo info{};if(p.controller->getParameterInfo(i,info)==kResultOk)p.performEdit(info.id,p.controller->getParamNormalized(info.id));}
}
CFPropertyListRef VST3Effect::copyState() const{
    auto& p=*impl;if(!p.component)return nullptr;MemoryStream state,controller;
    if(p.component->getState(&state)!=kResultOk)return nullptr;if(p.controller)p.controller->getState(&controller);
    NSDictionary* result=@{@"format":@"VST3",@"path":[NSString stringWithUTF8String:vst.path.c_str()],@"cid":[NSString stringWithUTF8String:vst.cid.c_str()],@"component":[NSData dataWithBytes:state.getData() length:state.getSize()],@"controller":[NSData dataWithBytes:controller.getData() length:controller.getSize()]};return CFBridgingRetain(result);
}
OSStatus VST3Effect::restore(CFPropertyListRef value){
    id state=(__bridge id)value;if(![state isKindOfClass:NSDictionary.class]||![state[@"format"] isEqual:@"VST3"]||![state[@"cid"] isEqual:[NSString stringWithUTF8String:vst.cid.c_str()]])return kAudio_ParamError;
    NSData* a=state[@"component"];NSData* b=state[@"controller"];if(![a isKindOfClass:NSData.class]||![b isKindOfClass:NSData.class]||a.length>64*1024*1024||b.length>64*1024*1024)return kAudio_ParamError;
    auto& p=*impl;Edit discarded;while(p.toAudio.pop(discarded)){}while(p.toUI.pop(discarded)){}MemoryStream stream((void*)a.bytes,a.length);if(p.component->setState(&stream)!=kResultOk)return kAudio_ParamError;
    if(p.controller){stream.seek(0,IBStream::kIBSeekSet,nullptr);p.controller->setComponentState(&stream);if(b.length){MemoryStream ctrl((void*)b.bytes,b.length);p.controller->setState(&ctrl);}}return 0;
}
int runVST3Probe(const char* path){@autoreleasepool{
    auto m=module(path);if(!m->factory)return 2;if(auto* factory3=query<IPluginFactory3>(m->factory)){factory3->setHostContext(&hostContext());drop(factory3);}PFactoryInfo factory{};m->factory->getFactoryInfo(&factory);auto* f2=query<IPluginFactory2>(m->factory);NSMutableArray* list=[NSMutableArray new];
    for(int32 i=0;i<m->factory->countClasses();++i){PClassInfo info{};if(m->factory->getClassInfo(i,&info)!=kResultOk||strcmp(info.category,kVstAudioEffectClass))continue;PClassInfo2 more{};if(f2&&f2->getClassInfo2(i,&more)==kResultOk&&strstr(more.subCategories,"Instrument"))continue;
        std::string name=std::string(factory.vendor)+": "+info.name;[list addObject:@{@"path":[NSString stringWithUTF8String:path],@"cid":[NSString stringWithUTF8String:hexID(info.cid).c_str()],@"name":[NSString stringWithUTF8String:name.c_str()]}];}
    drop(f2);NSData* data=[NSPropertyListSerialization dataWithPropertyList:list format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];fwrite(data.bytes,1,data.length,stdout);return 0;
}}
std::vector<VST3Choice> cachedVST3Effects(){return VST3Catalog::cached(VST3Catalog::cacheURL());}
std::vector<VST3Choice> scanVST3Effects(std::string& report,bool force){
 return VST3Catalog::scan(@[@"/Library/Audio/Plug-Ins/VST3",[@"~/Library/Audio/Plug-Ins/VST3" stringByExpandingTildeInPath]],VST3Catalog::cacheURL(),force,[](NSString* path)->NSArray*{
    NSString* temp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createFileAtPath:temp contents:nil attributes:nil];NSFileHandle* file=[NSFileHandle fileHandleForWritingAtPath:temp];
    NSTask* task=[NSTask new];task.executableURL=NSBundle.mainBundle.executableURL;task.arguments=@[@"--vst3-probe",path];task.standardOutput=file;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    BOOL launched=[task launchAndReturnError:nil];BOOL timedOut=NO;NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:8];while(launched&&task.running&&deadline.timeIntervalSinceNow>0)[NSThread sleepForTimeInterval:.02];if(launched&&task.running){timedOut=YES;kill(task.processIdentifier,SIGKILL);[task waitUntilExit];}
    [file closeFile];NSData* data=[NSData dataWithContentsOfFile:temp];[NSFileManager.defaultManager removeItemAtPath:temp error:nil];if(!launched||timedOut||task.terminationStatus||data.length>8*1024*1024)return nil;
    id list=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;return [list isKindOfClass:NSArray.class]?list:nil;
 },report);
}
