// Deterministic, test-only VST3. Never installed in the user's plug-in folders.
#import <Cocoa/Cocoa.h>
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include <cstring>
using namespace Steinberg;using namespace Steinberg::Vst;
static const TUID cid={0x42,0x4f,0x58,0x54,0x45,0x53,0x54,0x31,1,2,3,4,5,6,7,8};
#define REFCOUNT uint32 refs=1;uint32 PLUGIN_API addRef() override{return ++refs;}uint32 PLUGIN_API release() override{auto r=--refs;if(!r)delete this;return r;}
#define QI(TYPE) if(FUnknownPrivate::iidEqual(id,TYPE::iid)){*obj=static_cast<TYPE*>(this);addRef();return kResultOk;}
@interface FixtureTarget:NSObject
@property void* handler;
- (void)change:(NSSlider*)sender;
@end
@implementation FixtureTarget
- (void)change:(NSSlider*)sender {auto* h=static_cast<IComponentHandler*>(self.handler);if(h){h->beginEdit(7);h->performEdit(7,sender.doubleValue);h->endEdit(7);}}
@end
class View final:public IPlugView {
    NSView* parent=nil;NSSlider* slider=nil;FixtureTarget* target=nil;IPlugFrame* frame=nullptr;
public:
    explicit View(IComponentHandler* h){target=[FixtureTarget new];target.handler=h;}
    REFCOUNT
    tresult PLUGIN_API queryInterface(const TUID id,void** obj) override{QI(IPlugView)*obj=nullptr;return kNoInterface;}
    tresult PLUGIN_API isPlatformTypeSupported(FIDString t) override{return strcmp(t,kPlatformTypeNSView)?kResultFalse:kResultTrue;}
    tresult PLUGIN_API attached(void* p,FIDString t) override{if(isPlatformTypeSupported(t)!=kResultTrue)return kResultFalse;parent=(__bridge NSView*)p;slider=[NSSlider sliderWithValue:0.5 minValue:0 maxValue:1 target:target action:@selector(change:)];slider.frame=NSMakeRect(20,50,280,30);slider.identifier=@"fixture-gain";[parent addSubview:slider];return kResultOk;}
    tresult PLUGIN_API removed() override{[slider removeFromSuperview];slider=nil;parent=nil;return kResultOk;}
    tresult PLUGIN_API onWheel(float) override{return kResultFalse;}
    tresult PLUGIN_API onKeyDown(char16,int16,int16) override{return kResultFalse;}
    tresult PLUGIN_API onKeyUp(char16,int16,int16) override{return kResultFalse;}
    tresult PLUGIN_API getSize(ViewRect* r) override{*r=ViewRect(0,0,320,140);return kResultOk;}
    tresult PLUGIN_API onSize(ViewRect*) override{return kResultOk;}
    tresult PLUGIN_API onFocus(TBool) override{return kResultOk;}
    tresult PLUGIN_API setFrame(IPlugFrame* f) override{frame=f;return kResultOk;}
    tresult PLUGIN_API canResize() override{return kResultFalse;}
    tresult PLUGIN_API checkSizeConstraint(ViewRect*) override{return kResultFalse;}
};
class Effect final:public IComponent,public IAudioProcessor,public IEditController {
    bool sidechain=getenv("BOX_FIXTURE_SIDECHAIN")!=nullptr,auxActive=true;
    double gain=1,normalized=0.5;IComponentHandler* handler=nullptr;bool active=false,processing=false;
public:
    REFCOUNT
    tresult PLUGIN_API queryInterface(const TUID id,void** obj) override{QI(IComponent) QI(IAudioProcessor) QI(IEditController) if(FUnknownPrivate::iidEqual(id,FUnknown::iid)){*obj=static_cast<IComponent*>(this);addRef();return kResultOk;}*obj=nullptr;return kNoInterface;}
    tresult PLUGIN_API initialize(FUnknown*) override{return kResultOk;}
    tresult PLUGIN_API terminate() override{return kResultOk;}
    tresult PLUGIN_API getControllerClassId(TUID) override{return kResultFalse;}
    tresult PLUGIN_API setIoMode(IoMode) override{return kResultOk;}
    int32 PLUGIN_API getBusCount(MediaType t,BusDirection d) override{return t==kAudio?(sidechain&&d==kInput?2:1):0;}
    tresult PLUGIN_API getBusInfo(MediaType t,BusDirection d,int32 i,BusInfo& b) override{if(t!=kAudio||i<0||i>=getBusCount(t,d))return kInvalidArgument;b={};b.mediaType=t;b.direction=d;b.channelCount=2;b.busType=i==0?kMain:kAux;b.flags=BusInfo::kDefaultActive;return kResultOk;}
    tresult PLUGIN_API getRoutingInfo(RoutingInfo&,RoutingInfo&) override{return kNotImplemented;}
    tresult PLUGIN_API activateBus(MediaType t,BusDirection d,int32 b,TBool state) override{if(t==kAudio&&d==kInput&&b==1)auxActive=state;return kResultOk;}
    tresult PLUGIN_API setActive(TBool v) override{active=v;return kResultOk;}
    tresult PLUGIN_API setState(IBStream* s) override{int32 count=0;auto r=s->read(&gain,sizeof(gain),&count);normalized=gain/2;return count==sizeof(gain)?r:kResultFalse;}
    tresult PLUGIN_API getState(IBStream* s) override{return s->write(&gain,sizeof(gain),nullptr);}
    tresult PLUGIN_API setComponentState(IBStream*) override{return kResultOk;}
    tresult PLUGIN_API setBusArrangements(SpeakerArrangement* i,int32 ni,SpeakerArrangement* o,int32 no) override{return ni==(sidechain?2:1)&&no==1&&*i==SpeakerArr::kStereo&&(!sidechain||i[1]==SpeakerArr::kStereo)&&*o==SpeakerArr::kStereo?kResultOk:kResultFalse;}
    tresult PLUGIN_API getBusArrangement(BusDirection d,int32 i,SpeakerArrangement& a) override{a=SpeakerArr::kStereo;return i>=0&&i<getBusCount(kAudio,d)?kResultOk:kInvalidArgument;}
    tresult PLUGIN_API canProcessSampleSize(int32 s) override{return s==kSample32?kResultTrue:kResultFalse;}
    uint32 PLUGIN_API getLatencySamples() override{return 0;}
    tresult PLUGIN_API setupProcessing(ProcessSetup& s) override{return s.maxSamplesPerBlock<=4096&&s.symbolicSampleSize==kSample32?kResultOk:kResultFalse;}
    tresult PLUGIN_API setProcessing(TBool b) override{processing=b;return getenv("BOX_FIXTURE_OPTIONAL_PROCESSING")?kNotImplemented:kResultOk;}
    tresult PLUGIN_API process(ProcessData& d) override{
        if(!active||!processing)return kResultFalse;
        if(sidechain){if(auxActive||d.numInputs!=2||d.inputs[1].numChannels!=2||!d.inputs[1].channelBuffers32||d.inputs[1].channelBuffers32[0]||d.inputs[1].channelBuffers32[1])return kResultFalse;}

        if(d.inputParameterChanges)for(int32 i=0;i<d.inputParameterChanges->getParameterCount();++i){auto* q=d.inputParameterChanges->getParameterData(i);int32 offset;double value;if(q->getParameterId()==7&&q->getPoint(q->getPointCount()-1,offset,value)==kResultOk)gain=value*2;}
        for(int c=0;c<2;++c)for(int i=0;i<d.numSamples;++i)d.outputs[0].channelBuffers32[c][i]=float(d.inputs[0].channelBuffers32[c][i]*gain);return kResultOk;
    }
    uint32 PLUGIN_API getTailSamples() override{return 0;}
    int32 PLUGIN_API getParameterCount() override{return 1;}
    tresult PLUGIN_API getParameterInfo(int32 i,ParameterInfo& p) override{if(i)return kInvalidArgument;p={};p.id=7;p.defaultNormalizedValue=0.5;p.flags=ParameterInfo::kCanAutomate;return kResultOk;}
    tresult PLUGIN_API getParamStringByValue(ParamID,ParamValue,String128) override{return kNotImplemented;}
    tresult PLUGIN_API getParamValueByString(ParamID,TChar*,ParamValue&) override{return kNotImplemented;}
    ParamValue PLUGIN_API normalizedParamToPlain(ParamID,ParamValue v) override{return v*2;}
    ParamValue PLUGIN_API plainParamToNormalized(ParamID,ParamValue v) override{return v/2;}
    ParamValue PLUGIN_API getParamNormalized(ParamID) override{return normalized;}
    tresult PLUGIN_API setParamNormalized(ParamID,ParamValue v) override{normalized=v;return kResultOk;}
    tresult PLUGIN_API setComponentHandler(IComponentHandler* h) override{handler=h;return kResultOk;}
    IPlugView* PLUGIN_API createView(FIDString name) override{return strcmp(name,ViewType::kEditor)?nullptr:new View(handler);}
};
class Factory final:public IPluginFactory {
public:
    REFCOUNT
    tresult PLUGIN_API queryInterface(const TUID id,void** obj) override{QI(IPluginFactory)*obj=nullptr;return kNoInterface;}
    tresult PLUGIN_API getFactoryInfo(PFactoryInfo* f) override{*f={};strcpy(f->vendor,"BOX Tests");return kResultOk;}
    int32 PLUGIN_API countClasses() override{return 1;}
    tresult PLUGIN_API getClassInfo(int32 i,PClassInfo* c) override{if(i)return kInvalidArgument;*c={};memcpy(c->cid,cid,16);strcpy(c->category,kVstAudioEffectClass);strcpy(c->name,"Deterministic Gain");c->cardinality=PClassInfo::kManyInstances;return kResultOk;}
    tresult PLUGIN_API createInstance(FIDString id,FIDString iid,void** obj) override{if(memcmp(id,cid,16))return kInvalidArgument;auto* e=new Effect;auto result=e->queryInterface(iid,obj);e->release();return result;}
};
extern "C" bool bundleEntry(CFBundleRef){return true;}
extern "C" bool bundleExit(){return true;}
extern "C" IPluginFactory* GetPluginFactory(){return new Factory;}
