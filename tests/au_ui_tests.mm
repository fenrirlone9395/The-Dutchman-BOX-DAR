#import <Cocoa/Cocoa.h>
#import "../src/plugins/AURackUI.h"
#include <cassert>
#include <iostream>
@interface AURackUI (TestAccess)
- (void)editor:(NSButton*)sender;
- (void)remove:(NSButton*)sender;
- (void)applyPresetURL:(NSURL*)url index:(NSInteger)index;
@end
int main() { @autoreleasepool {
    [NSApplication sharedApplication];
    AURack rack;
    rack.slots.push_back(std::make_unique<AUEffect>(AUChoice{{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple AUHipass"}));
    assert(rack.prepare(48000)==0 && rack.slots[0]->error==0);
    AURackUI* ui=[[AURackUI alloc] initWithRack:&rack]; [ui show];
    NSButton* button=[NSButton new]; button.tag=0; [ui editor:button];
    bool found=false;
    for(NSWindow* window in NSApp.windows) if([window.title hasPrefix:@"Apple AUHipass"]) { found=true; std::cout<<"Editor: "<<window.title.UTF8String<<std::endl; assert([window isKindOfClass:NSPanel.class]); assert(window.level==NSFloatingWindowLevel); assert(!window.canBecomeMainWindow); assert([window.contentView isKindOfClass:NSScrollView.class]);
        NSScrollView* scroll=(NSScrollView*)window.contentView;
        NSSize original=scroll.documentView.frame.size;
        [scroll.documentView setFrameSize:NSMakeSize(2400,1800)];
        assert(window.frame.size.width<=window.screen.visibleFrame.size.width);
        assert(window.frame.size.height<=window.screen.visibleFrame.size.height);
        assert(scroll.documentView.frame.size.width==2400);
        [scroll.documentView setFrameSize:original]; }
    assert(found);
    [ui setEditingAllowed:NO]; [ui refreshStatus]; [ui closeEditors];
    [ui setEditingAllowed:YES]; [ui editor:button]; [ui closeEditors];
    NSWindow* host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSView* embedded=[ui embeddedView]; [host.contentView addSubview:embedded];
    [embedded.widthAnchor constraintEqualToConstant:900].active=YES;
    [host.contentView layoutSubtreeIfNeeded]; assert(embedded.superview==host.contentView);
    __block int before=0,after=0;
    ui.beforeEdit=^{++before;}; ui.afterEdit=^{++after;};
    assert(AudioUnitSetParameter(rack.slots[0]->handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,2000,0)==0);
    CFPropertyListRef raw=rack.slots[0]->copyState();assert(raw);
    id state=CFBridgingRelease(raw);
    NSURL* file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".aupreset"]]];
    NSData* data=[NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];assert(data);assert([data writeToURL:file atomically:YES]);
    assert(AudioUnitSetParameter(rack.slots[0]->handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,500,0)==0);
    [ui applyPresetURL:file index:0];
    AudioUnitParameterValue cutoff=0;assert(AudioUnitGetParameter(rack.slots[0]->handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,&cutoff)==0);assert(std::abs(cutoff-2000)<1);assert(before==1 && after==1);
    NSMutableDictionary* wrong=[state mutableCopy];wrong[@"subtype"]=@0;
    data=[NSPropertyListSerialization dataWithPropertyList:wrong format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];assert([data writeToURL:file atomically:YES]);
    [ui applyPresetURL:file index:0];assert(before==1 && after==1);
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    [ui remove:button]; assert(rack.slots.size()==1 && !rack.slots[0]); assert(before==2 && after==2);
    std::cout<<"PASS: .aupreset file restore and component mismatch rejection; embedded rack mutation hooks; rack UI construction, editor creation/reopen/teardown\n";
} }
