#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#include "Output.hpp"
#include "ProcessTap.hpp"
#include <memory>
#import "MeterView.h"
#import "Theme.h"
#import "SpatialView.h"
#import "RackControls.h"
#import "plugins/AURackUI.h"

@interface DARDocument : NSView
@property(copy) void (^arrange)(NSSize);
@end
@implementation DARDocument
- (BOOL)isFlipped { return YES; }
- (void)layout { [super layout];if(self.arrange)self.arrange(self.bounds.size); }
- (void)drawRect:(NSRect)rect {
    [DARDeep() setFill];NSRectFill(self.bounds);
    NSBezierPath* red=[NSBezierPath bezierPath];[red moveToPoint:NSMakePoint(490,0)];[red lineToPoint:NSMakePoint(510,0)];[red lineToPoint:NSMakePoint(490,30)];[red lineToPoint:NSMakePoint(470,30)];[red closePath];[DARRed() setFill];[red fill];
    NSBezierPath* amber=[NSBezierPath bezierPath];[amber moveToPoint:NSMakePoint(515,0)];[amber lineToPoint:NSMakePoint(525,0)];[amber lineToPoint:NSMakePoint(505,30)];[amber lineToPoint:NSMakePoint(495,30)];[amber closePath];[DARAmber() setFill];[amber fill];
}
@end

@interface RackApp : NSObject <NSApplicationDelegate,SCStreamOutput,SCStreamDelegate,SCContentSharingPickerObserver> {
    AudioBridge bridge;
    AURack auRack;
    std::unique_ptr<ProcessTap> processTap;
    BOOL systemTapSelected;
    AURackUI* auUI;
    std::unique_ptr<Output> output;
    dispatch_queue_t captureQueue;
    SCStream* stream;
    SCContentFilter* selectedFilter;
    NSWindow* window;
    NSPopUpButton* devices;
    NSButton *startButton,*selectButton,*systemButton,*muteButton,*refreshButton;
    NSTextField *status,*meters,*sourceLabel;
    NSTimer* timer;
    DARMeterView *inputView,*outputView;
    NSMutableArray<NSTextField*>* parameterLabels;
    NSMutableArray<NSSlider*>* parameterSliders;
    NSTextField* reductionLabel;
    DARGraphicEQ* geq;
    DARGraphicEQ* eqMini;
    NSPanel* eqPanel;
    NSPanel* spatialPanel;
    DARSpatialView* spatialView;
    NSButton* spatialSummary;
    NSButton* eqSummary;
    double lastDeviceCheck,lastPresetCheck;
    BOOL editWasRunning;
    BOOL busy,running;
    AudioDeviceID activeDevice;
    std::atomic<bool> accepting;
}
@end
@implementation RackApp
- (NSButton*)button:(NSString*)title action:(SEL)action {
    DARButton* b=[DARButton buttonWithTitle:title target:self action:action];return b;
}
- (void)applicationDidFinishLaunching:(NSNotification*)note {
    (void)note;
    processTap=std::make_unique<ProcessTap>(bridge);
    bridge.rack=&auRack;
    auUI=[[AURackUI alloc] initWithRack:&auRack];
    output=std::make_unique<Output>(bridge);
    __weak RackApp* weakSelf=self;
    auUI.beforeEdit=^{ [weakSelf beginRackEdit]; };
    auUI.afterEdit=^{ [weakSelf endRackEdit]; };
    captureQueue=dispatch_queue_create("audio.rack.capture",DISPATCH_QUEUE_SERIAL);
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1160,760) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.title=@"The Dutchman BOX/DAR — Listening Rack";
    window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor=DARDeep();
    window.contentMinSize=NSMakeSize(1080,700);
    DARDocument* canvas=[[DARDocument alloc] initWithFrame:window.contentView.bounds]; canvas.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; window.contentView=canvas;
    void (^add)(NSView*)=^(NSView* v){v.translatesAutoresizingMaskIntoConstraints=YES;[canvas addSubview:v];};
    NSTextField* title=[NSTextField labelWithString:@"THE DUTCHMAN  /  BOX·DAR"];title.font=[NSFont boldSystemFontOfSize:17];add(title);
    selectButton=[self button:@"Application…" action:@selector(selectSource:)];add(selectButton);
    systemButton=[self button:@"System Audio" action:@selector(systemSource:)];add(systemButton);
    devices=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];devices.target=self;devices.action=@selector(deviceChanged:);add(devices);
    refreshButton=[self button:@"↻" action:@selector(refresh:)];add(refreshButton);
    startButton=[self button:@"Start" action:@selector(toggle:)];add(startButton);
    muteButton=[self button:@"出力を有効にする" action:@selector(mute:)];((DARButton*)muteButton).primary=YES;add(muteButton);
    sourceLabel=[NSTextField labelWithString:@"入力：未選択 / Stereo"];sourceLabel.font=[NSFont systemFontOfSize:10];sourceLabel.textColor=DARColor(0x9CAEC5);add(sourceLabel);
    NSView* rackView=[auUI embeddedView];add(rackView);
    DARFaceplate* inputPanel=[DARFaceplate new];DARFaceplate* outputPanel=[DARFaceplate new];DARFaceplate* limiterPanel=[DARFaceplate new];DARFaceplate* eqCard=[DARFaceplate new];add(inputPanel);add(outputPanel);add(limiterPanel);add(eqCard);
    inputView=[[DARMeterView alloc] initWithTitle:@"INPUT"];inputView.vertical=YES;[inputPanel addSubview:inputView];
    outputView=[[DARMeterView alloc] initWithTitle:@"OUTPUT"];outputView.vertical=YES;[outputPanel addSubview:outputView];
    DARGainKnob* inKnob=[DARGainKnob new];inKnob.minimum=-24;inKnob.maximum=12;inKnob.caption=@"INPUT GAIN";inKnob.target=self;inKnob.action=@selector(gainKnob:);inKnob.tag=0;[inputPanel addSubview:inKnob];
    DARGainKnob* outKnob=[DARGainKnob new];outKnob.minimum=-60;outKnob.maximum=6;outKnob.caption=@"MASTER GAIN";outKnob.target=self;outKnob.action=@selector(gainKnob:);outKnob.tag=1;[outputPanel addSubview:outKnob];
    NSTextField* limiterTitle=[NSTextField labelWithString:@"MASTER LIMITER"];limiterTitle.textColor=DARAmber();[limiterPanel addSubview:limiterTitle];
    NSButton* limiter=[NSButton checkboxWithTitle:@"Bypass" target:self action:@selector(bypass:)];limiter.tag=3;[limiterPanel addSubview:limiter];
    reductionLabel=[NSTextField labelWithString:@"−1.0 dBFS / GR 0.0 dB"];reductionLabel.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];[limiterPanel addSubview:reductionLabel];
    eqSummary=[self button:@"MASTER EQ  ▸" action:@selector(showEQ:)];[eqCard addSubview:eqSummary];
    NSTextField* eqCaption=[NSTextField labelWithString:@"15 bands · click to edit"];eqCaption.font=[NSFont systemFontOfSize:11];eqCaption.textColor=DARAmber();[eqCard addSubview:eqCaption];
    eqMini=[[DARGraphicEQ alloc] initWithParameters:&bridge.parameters];eqMini.compact=YES;eqMini.cell=[NSActionCell new];eqMini.target=self;eqMini.action=@selector(showEQ:);[eqCard addSubview:eqMini];
    geq=[[DARGraphicEQ alloc] initWithParameters:&bridge.parameters];
    eqPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,940,280) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];eqPanel.releasedWhenClosed=NO;eqPanel.title=@"The Dutchman — Master EQ";eqPanel.level=NSFloatingWindowLevel;eqPanel.hidesOnDeactivate=YES;eqPanel.backgroundColor=DARDeep();eqPanel.appearance=window.appearance;
    DARDocument* eqCanvas=[[DARDocument alloc] initWithFrame:eqPanel.contentView.bounds];eqPanel.contentView=eqCanvas;geq.frame=NSMakeRect(10,34,920,240);[eqCanvas addSubview:geq];
    NSButton* eqBypass=[NSButton checkboxWithTitle:@"Bypass" target:self action:@selector(bypass:)];eqBypass.tag=1;eqBypass.frame=NSMakeRect(14,6,90,24);[eqCanvas addSubview:eqBypass];
    NSButton* flat=[self button:@"Flat" action:@selector(flatEQ:)];flat.frame=NSMakeRect(114,4,70,26);[eqCanvas addSubview:flat];
    spatialSummary=[self button:@"SPATIAL · OFF  ▸" action:@selector(showSpatial:)];[eqCard addSubview:spatialSummary];
    spatialPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,760,520) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];spatialPanel.releasedWhenClosed=NO;spatialPanel.title=@"The Dutchman — Spatial Listening";spatialPanel.level=NSFloatingWindowLevel;spatialPanel.hidesOnDeactivate=YES;spatialPanel.backgroundColor=DARDeep();spatialPanel.appearance=window.appearance;
    DARDocument* spatialCanvas=[[DARDocument alloc] initWithFrame:spatialPanel.contentView.bounds];spatialPanel.contentView=spatialCanvas;
    spatialView=[[DARSpatialView alloc] initWithParameters:&bridge.spatialParameters];spatialView.frame=NSMakeRect(0,40,760,480);[spatialCanvas addSubview:spatialView];
    NSButton* crossfeed=[NSButton checkboxWithTitle:@"Crossfeed 有効" target:self action:@selector(enableSpatial:)];crossfeed.frame=NSMakeRect(18,8,180,24);[spatialCanvas addSubview:crossfeed];
    NSButton* resetField=[self button:@"Reset Field" action:@selector(resetSpatial:)];resetField.frame=NSMakeRect(206,6,124,28);[spatialCanvas addSubview:resetField];
    meters=[NSTextField labelWithString:@"Stopped"];meters.font=[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];meters.textColor=DARColor(0x9CAEC5);add(meters);
    status=[NSTextField labelWithString:@"停止中"];status.font=[NSFont systemFontOfSize:10];status.textColor=DARAmber();add(status);
    __weak DARDocument* weakCanvas=canvas;
    canvas.arrange=^(NSSize size){
        CGFloat w=size.width,h=size.height,side=260,x=w-side-14,top=94,available=h-top-42,panel=(available-244)/2;
        title.frame=NSMakeRect(16,8,600,25);selectButton.frame=NSMakeRect(16,42,112,30);systemButton.frame=NSMakeRect(136,42,118,30);devices.frame=NSMakeRect(270,42,280,30);refreshButton.frame=NSMakeRect(558,42,34,30);
        startButton.frame=NSMakeRect(w-390,40,88,32);muteButton.frame=NSMakeRect(w-292,40,278,32);sourceLabel.frame=NSMakeRect(18,76,w-32,14);
        rackView.frame=NSMakeRect(14,top,x-26,available);
        inputPanel.frame=NSMakeRect(x,top,side,panel);outputPanel.frame=NSMakeRect(x,top+panel+10,side,panel);
        for(NSView* meter in @[inputView,outputView])meter.frame=NSMakeRect(8,8,102,panel-16);
        inKnob.frame=outKnob.frame=NSMakeRect(132,12,118,112);
        CGFloat y=top+2*panel+20;limiterPanel.frame=NSMakeRect(x,y,side,82);limiterTitle.frame=NSMakeRect(12,10,170,20);limiter.frame=NSMakeRect(174,8,80,24);reductionLabel.frame=NSMakeRect(12,46,240,20);
        eqCard.frame=NSMakeRect(x,y+92,side,142);spatialSummary.frame=NSMakeRect(12,104,side-24,28);eqSummary.frame=NSMakeRect(12,10,side-24,32);eqCaption.frame=NSMakeRect(18,80,side-30,16);eqMini.frame=NSMakeRect(12,46,side-24,30);
        meters.frame=NSMakeRect(16,h-26,w-280,18);status.frame=NSMakeRect(w-260,h-26,246,18);
        [weakCanvas setNeedsDisplay:YES];
    };
    canvas.arrange(canvas.bounds.size);
    [self refresh:nil];
    if(NSProcessInfo.processInfo.arguments.count==3 && ([NSProcessInfo.processInfo.arguments[1] isEqualToString:@"--preview"] || [NSProcessInfo.processInfo.arguments[1] isEqualToString:@"--spatial-preview"])) {
        for(int i=0;i<4;++i){auto unit=std::make_unique<AUEffect>(AUChoice{{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple · AUHipass"});unit->prepare(48000);unit->markPreset("preview","Default");auRack.slots.push_back(std::move(unit));}
        [auUI rebuild];
        [window center];[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
        NSWindow* previewWindow=window;
        if([NSProcessInfo.processInfo.arguments[1] isEqualToString:@"--spatial-preview"]){[self showSpatial:nil];previewWindow=spatialPanel;}
        NSLog(@"Rendering UI preview");
        {
            [previewWindow.contentView layoutSubtreeIfNeeded];
            __block BOOL saved=NO;
            [previewWindow.effectiveAppearance performAsCurrentDrawingAppearance:^{
                NSBitmapImageRep* image=[previewWindow.contentView bitmapImageRepForCachingDisplayInRect:previewWindow.contentView.bounds];
                [previewWindow.contentView cacheDisplayInRect:previewWindow.contentView.bounds toBitmapImageRep:image];
                saved=[[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:NSProcessInfo.processInfo.arguments[2] atomically:YES];
            }];std::exit(saved?0:1);
        }return;
    }
    SCContentSharingPicker* picker=SCContentSharingPicker.sharedPicker;
    SCContentSharingPickerConfiguration* config=[SCContentSharingPickerConfiguration new];
    config.allowedPickerModes=SCContentSharingPickerModeSingleApplication;
    config.excludedBundleIDs=NSBundle.mainBundle.bundleIdentifier?@[NSBundle.mainBundle.bundleIdentifier]:@[]; config.allowsChangingSelectedContent=NO;
    picker.defaultConfiguration=config; [picker addObserver:self]; picker.active=YES;
    timer=[NSTimer scheduledTimerWithTimeInterval:1.0/30.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    NSMenu* menu=[NSMenu new]; NSMenuItem* root=[NSMenuItem new]; [menu addItem:root];
    root.submenu=[NSMenu new]; [root.submenu addItemWithTitle:@"Quit The Dutchman BOX/DAR" action:@selector(terminate:) keyEquivalent:@"q"]; NSApp.mainMenu=menu;
    [window center]; [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)showSpatial:(id)sender { [spatialPanel center];[spatialPanel makeKeyAndOrderFront:nil]; }
- (void)enableSpatial:(NSButton*)sender { bridge.spatialParameters.enabled=sender.state==NSControlStateValueOn;spatialView.needsDisplay=YES;spatialSummary.title=bridge.spatialParameters.enabled?@"SPATIAL · CROSSFEED  ▸":@"SPATIAL · OFF  ▸"; }
- (void)resetSpatial:(id)sender { [spatialView resetField]; }
- (void)showEQ:(id)sender { [eqPanel center];[eqPanel makeKeyAndOrderFront:nil]; }
- (void)gainKnob:(DARGainKnob*)knob { if(knob.tag==0)bridge.parameters.inputDB=knob.floatValue;else bridge.parameters.masterDB=knob.floatValue; }
- (void)bypass:(NSButton*)sender {
    bool value=sender.state==NSControlStateValueOn;
    switch(sender.tag) {
        case 1: bridge.parameters.eqBypass=value; geq.needsDisplay=YES; break;
        case 3: bridge.parameters.limiterBypass=value; break;
    }
}
- (void)flatEQ:(id)sender { [geq flatten]; }
- (void)beginRackEdit { editWasRunning=running; if(editWasRunning) output->pause(); }
- (void)endRackEdit {
    if(editWasRunning) { OSStatus error=output->resume(); if(error) [self stopWithMessage:@"出力の再開に失敗しました。"]; }
    editWasRunning=NO;
}
- (void)showAURack:(id)sender { [auUI show]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return YES; }
- (void)applicationWillTerminate:(NSNotification*)note { accepting=false; bridge.muted=true; output->stop(); processTap->stop(); [auUI closeEditors]; [stream stopCaptureWithCompletionHandler:nil]; }
- (void)controls {
    [auUI setEditingAllowed:!busy];
    startButton.enabled=!busy && (running || ((selectedFilter || systemTapSelected) && devices.numberOfItems));
    startButton.title=running?@"Stop":@"Start";
    selectButton.enabled=systemButton.enabled=refreshButton.enabled=!busy&&!running;
    devices.enabled=!busy; muteButton.enabled=running&&!busy;
    muteButton.title=bridge.muted?@"出力を有効にする":@"Emergency Mute";
    if(running&&!busy) status.stringValue=bridge.muted?@"● MUTED — 出力ミュート中":@"● LIVE — 音声処理・出力中";
}
- (void)refresh:(id)sender {
    NSNumber* old=devices.selectedItem.representedObject;
    [devices removeAllItems];
    for(auto& d:outputDevices()) { [devices addItemWithTitle:[NSString stringWithUTF8String:d.name.c_str()]]; devices.lastItem.representedObject=@(d.id); if([old isEqual:@(d.id)]) [devices selectItem:devices.lastItem]; }
    [self controls];
}
- (void)selectSource:(id)sender { [SCContentSharingPicker.sharedPicker present]; }
- (void)systemSource:(id)sender {
    if(@available(macOS 14.2,*)) {
        systemTapSelected=YES;
        sourceLabel.stringValue=@"入力：System Audio / 通常出力のch 1/2・Direct Tap（Start中は元音声ミュート）";
        [self controls];
    } else status.stringValue=@"元音声のミュートにはmacOS 14.2以降が必要です。";
}

- (void)contentSharingPicker:(SCContentSharingPicker*)picker didUpdateWithFilter:(SCContentFilter*)filter forStream:(SCStream*)s {
    dispatch_async(dispatch_get_main_queue(),^{ if(!running&&!busy) { systemTapSelected=NO; selectedFilter=filter; sourceLabel.stringValue=@"入力：標準ピッカーで選択したアプリ / 48,000 Hz / Stereo"; [self controls]; } });
}
- (void)contentSharingPicker:(SCContentSharingPicker*)picker didCancelForStream:(SCStream*)s {}
- (void)contentSharingPickerStartDidFailWithError:(NSError*)error { dispatch_async(dispatch_get_main_queue(),^{ status.stringValue=error.localizedDescription; }); }
- (void)mute:(id)sender { bridge.muted=!bridge.muted.load(); [self controls]; }
- (void)deviceChanged:(id)sender { if(running) [self stopWithMessage:@"出力先を変更しました。Startで再開してください（ミュート）。"]; }
- (void)toggle:(id)sender {
    if(running) { [self stopWithMessage:@"停止中"]; return; }
    if(busy || (!selectedFilter && !systemTapSelected) || !devices.selectedItem) return;
    busy=YES; bridge.reset(); [inputView clearHold]; [outputView clearHold]; [self controls];
    activeDevice=[devices.selectedItem.representedObject unsignedIntValue];
    OSStatus result=output->start(activeDevice);
    if(result) { busy=NO; status.stringValue=[NSString stringWithFormat:@"出力開始失敗: %d",(int)result]; [self controls]; return; }
    auUI.processingRate=output->rate; geq.sampleRate=output->rate; geq.needsDisplay=YES;
    if(systemTapSelected) {
        result=processTap->start();
        busy=NO;
        if(result) { output->stop(); status.stringValue=[NSString stringWithFormat:@"System Tap開始失敗: %d（音声収録権限を確認）",(int)result]; }
        else running=YES;
        [self controls]; return;
    }
    bridge.captureRate=48000;
    SCStreamConfiguration* config=[SCStreamConfiguration new];
    config.capturesAudio=YES; config.excludesCurrentProcessAudio=YES; config.sampleRate=48000; config.channelCount=2;
    config.width=2; config.height=2; config.minimumFrameInterval=CMTimeMake(1,1);
    stream=[[SCStream alloc] initWithFilter:selectedFilter configuration:config delegate:self];
    NSError* error=nil;
    if(![stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:captureQueue error:&error]) {
        output->stop(); stream=nil; busy=NO; status.stringValue=error.localizedDescription; [self controls]; return;
    }
    accepting=true;
    [stream startCaptureWithCompletionHandler:^(NSError* error) {
        dispatch_async(dispatch_get_main_queue(),^{
            if(error) { [self stopWithMessage:error.localizedDescription]; }
            else { busy=NO; running=YES; status.stringValue=@"実行中・ミュート。経路を確認後、出力を有効にしてください。"; [self controls]; }
        });
    }];
}
- (void)stopWithMessage:(NSString*)message {
    accepting=false; busy=YES; running=NO; output->stop(); [self controls];
    processTap->stop();
    if(!stream) { busy=NO; status.stringValue=message; [self controls]; return; }
    SCStream* old=stream;
    [old stopCaptureWithCompletionHandler:^(NSError* error) {
        dispatch_async(captureQueue,^{ dispatch_async(dispatch_get_main_queue(),^{
            stream=nil; busy=NO; status.stringValue=error ? [message stringByAppendingFormat:@" (停止: %@)",error.localizedDescription] : message; [self controls];
        }); });
    }];
}
- (void)stream:(SCStream*)s didStopWithError:(NSError*)error {
    dispatch_async(dispatch_get_main_queue(),^{ if(s==stream && !busy) [self stopWithMessage:error.localizedDescription]; });
}
- (void)stream:(SCStream*)s didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(!accepting.load() || type!=SCStreamOutputTypeAudio || !CMSampleBufferDataIsReady(sample)) return;
    const AudioStreamBasicDescription* format=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
    if(!format || format->mFormatID!=kAudioFormatLinearPCM || !(format->mFormatFlags&kAudioFormatFlagIsFloat) || format->mBitsPerChannel!=32 || format->mChannelsPerFrame!=2 || format->mSampleRate!=48000) { ++bridge.invalid; return; }
    struct { AudioBufferList list; AudioBuffer extra; } storage{};
    CMBlockBufferRef block=nullptr; size_t required=0;
    OSStatus code=CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,&required,&storage.list,sizeof(storage),nullptr,nullptr,0,&block);
    if(code) { ++bridge.invalid; if(block) CFRelease(block); return; }
    auto& list=storage.list; size_t frames=CMSampleBufferGetNumSamples(sample);
    if(list.mNumberBuffers==2 && list.mBuffers[0].mData && list.mBuffers[1].mData && list.mBuffers[0].mDataByteSize>=frames*4 && list.mBuffers[1].mDataByteSize>=frames*4)
        bridge.push((float*)list.mBuffers[0].mData,(float*)list.mBuffers[1].mData,frames,1);
    else if(list.mNumberBuffers==1 && list.mBuffers[0].mData && list.mBuffers[0].mDataByteSize>=frames*8)
        bridge.push((float*)list.mBuffers[0].mData,(float*)list.mBuffers[0].mData+1,frames,2);
    else ++bridge.invalid;
    if(block) CFRelease(block);
}
- (void)tick:(NSTimer*)t {
    double now=NSProcessInfo.processInfo.systemUptime;
    float il=bridge.inputMeter.peaks[0].exchange(0),ir=bridge.inputMeter.peaks[1].exchange(0);
    float ol=bridge.outputMeter.peaks[0].exchange(0),orr=bridge.outputMeter.peaks[1].exchange(0);
    [inputView updateLeft:il right:ir time:now]; [outputView updateLeft:ol right:orr time:now];
    reductionLabel.stringValue=[NSString stringWithFormat:@"−1.0 dBFS / GR %.1f dB%@",bridge.gainReduction.exchange(0),bridge.parameters.limiterBypass?@"  (BYPASS)":@""];
    meters.stringValue=[NSString stringWithFormat:@"Queue %.1f ms  |  Underrun %llu / Overrun %llu / Invalid %llu  |  Output %.0f Hz · %u frames",bridge.queued()*1000/bridge.captureRate.load(),bridge.underruns.load(),bridge.overruns.load(),bridge.invalid.load(),output->rate,output->bufferFrames];
    spatialSummary.title=bridge.spatialParameters.enabled?@"SPATIAL · CROSSFEED  ▸":@"SPATIAL · OFF  ▸";
    eqMini.sampleRate=geq.sampleRate;eqMini.needsDisplay=YES;
    eqSummary.title=bridge.parameters.eqBypass?@"MASTER EQ · BYPASS  ▸":@"MASTER EQ  ▸";
    if(running&&!busy) [self controls];
    if(!busy && now-lastPresetCheck>=0.2) { lastPresetCheck=now; [auUI refreshStatus]; }
    if(running&&!busy && now-lastDeviceCheck>=0.2) {
        lastDeviceCheck=now;
        AudioObjectPropertyAddress a{kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; UInt32 alive=0,size=sizeof(alive);
        OSStatus err=AudioObjectGetPropertyData(activeDevice,&a,0,nullptr,&size,&alive);
        double rate=0; a.mSelector=kAudioDevicePropertyNominalSampleRate; size=sizeof(rate);
        OSStatus rateErr=AudioObjectGetPropertyData(activeDevice,&a,0,nullptr,&size,&rate);
        if(systemTapSelected && !processTap->sourceIsCurrent()) { [self stopWithMessage:@"macOSの通常出力先が変わりました。Startで取り込み直してください。"]; return; }
        if(err||!alive||rateErr||rate!=output->rate) [self stopWithMessage:@"出力デバイス切断またはレート変更を検出して停止しました。"];
    }
}
@end
int main() { @autoreleasepool { NSApplication* app=NSApplication.sharedApplication; app.activationPolicy=NSApplicationActivationPolicyRegular; RackApp* delegate=[RackApp new]; app.delegate=delegate; [app run]; return 0; } }
