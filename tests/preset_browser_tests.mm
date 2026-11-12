#import <Cocoa/Cocoa.h>
#import "../src/plugins/AURackUI.h"
#include <cassert>
#include <iostream>
@interface AURackUI (BrowserTest)
- (void)applyPresetURL:(NSURL*)url index:(NSInteger)index;
- (NSArray*)presetOptions:(NSInteger)index;
- (NSMenu*)presetMenuForIndex:(NSInteger)index;
- (void)stepPreset:(NSInteger)index direction:(NSInteger)direction;
- (NSDictionary*)presetMetadata:(AUEffect*)slot;
- (void)restorePresetMetadata:(id)data slot:(AUEffect*)slot;
@end
@interface TestBrowser : AURackUI
@property(strong) NSArray* testOptions;
@end
@implementation TestBrowser
- (NSArray*)presetOptions:(NSInteger)index { return self.testOptions; }
@end
static void cutoff(AUEffect& unit,float value) { assert(AudioUnitSetParameter(unit.handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,value,0)==0); }
static float cutoff(AUEffect& unit) {float value=0;assert(AudioUnitGetParameter(unit.handle(),kHipassParam_CutoffFrequency,kAudioUnitScope_Global,0,&value)==0);return value;}
static int checked(NSMenu* menu) {int count=0;for(NSMenuItem* item in menu.itemArray) {if(item.state==NSControlStateValueOn)++count;if(item.submenu)count+=checked(item.submenu);}return count;}
int main(){@autoreleasepool {
    [NSApplication sharedApplication];AURack rack;
    AUChoice choice{{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple AUHipass"};
    for(int i=0;i<2;++i){rack.slots.push_back(std::make_unique<AUEffect>(choice));assert(rack.slots.back()->prepare(48000)==0);}
    auto& unit=*rack.slots[0];
    NSURL* directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSMutableArray* options=[NSMutableArray new];
    for(int i=0;i<2;++i) {
        NSURL* folder=[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%d",i] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL* file=[folder URLByAppendingPathComponent:@"Same Name.aupreset"];
        cutoff(unit,i?8000:2000);CFPropertyListRef raw=unit.copyState();assert(raw);id state=CFBridgingRelease(raw);
        NSData* data=[NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];assert([data writeToURL:file atomically:YES]);
        [options addObject:@{@"key":[@"file:" stringByAppendingString:file.URLByStandardizingPath.path],@"name":@"Same Name",@"url":file}];
    }
    TestBrowser* ui=[[TestBrowser alloc] initWithRack:&rack];ui.testOptions=options;[ui show];
    [ui applyPresetURL:options[0][@"url"] index:0];assert(unit.presetName=="Same Name"&&!unit.presetModified&&!unit.presetBaseline.empty());assert(std::abs(cutoff(unit)-2000)<1);
    NSMenu* menu=[ui presetMenuForIndex:0];assert(checked(menu)==1);assert(menu.itemArray[0].submenu.itemArray[0].state==NSControlStateValueOn);assert(menu.itemArray[0].submenu.itemArray[1].state==NSControlStateValueOff);
    cutoff(unit,3000);[ui refreshStatus];assert(unit.presetModified);
    NSArray* buttons=[ui valueForKey:@"presetButtons"];assert([((NSButton*)buttons[0]).attributedTitle.string hasSuffix:@" *"]);
    assert(!rack.slots[1]->presetModified && rack.slots[1]->presetKey.empty());
    menu=[ui presetMenuForIndex:0];assert(checked(menu)==1);assert([menu.itemArray[0].submenu.itemArray[0].attributedTitle.string hasSuffix:@" *"]);
    cutoff(unit,2000);[ui refreshStatus];assert(!unit.presetModified);
    cutoff(unit,3500);[ui stepPreset:0 direction:1];assert(std::abs(cutoff(unit)-8000)<1&&!unit.presetModified);
    [ui stepPreset:0 direction:1];assert(std::abs(cutoff(unit)-2000)<1);
    [ui stepPreset:0 direction:-1];assert(std::abs(cutoff(unit)-8000)<1);
    cutoff(unit,7000);[ui refreshStatus];assert(unit.presetModified);
    NSDictionary* saved=[ui presetMetadata:&unit];
    AUEffect restored(choice);assert(restored.prepare(48000)==0);CFPropertyListRef raw=unit.copyState();assert(restored.restore(raw)==0);CFRelease(raw);
    [ui restorePresetMetadata:saved slot:&restored];assert(restored.presetKey==unit.presetKey && restored.presetName==unit.presetName && restored.presetModified);
    cutoff(restored,8000);restored.refreshPresetModified();assert(!restored.presetModified);
    [ui restorePresetMetadata:@{@"key":@1} slot:&restored];assert(restored.presetName=="Same Name");
    std::swap(rack.slots[0],rack.slots[1]);assert(rack.slots[1]->presetName=="Same Name"&&rack.slots[0]->presetKey.empty());
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];[ui closeEditors];
    std::cout<<"PASS: checked source identity with duplicate names, dirty marker, return-to-baseline, independent instances, +/- wraparound, reset dirty on load, reorder identity, preset metadata roundtrip\n";
}}
