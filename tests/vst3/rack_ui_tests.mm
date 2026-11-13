#import <Cocoa/Cocoa.h>
#include "../../src/plugins/VST3Host.hpp"
#import "../../src/plugins/AURackUI.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include "../../src/RackSettings.hpp"
@interface AURackUI (VST3Test)
- (BOOL)installEffect:(std::unique_ptr<RackEffect>)slot atIndex:(NSInteger)index;
- (void)addVST3:(NSMenuItem*)item;
- (void)addVST3Choice:(const VST3Choice&)choice;
- (void)editor:(NSButton*)sender;
- (void)up:(NSButton*)sender;
- (void)down:(NSButton*)sender;
- (void)remove:(NSButton*)sender;
@end
int main(int argc,char** argv){if(argc==3&&!strcmp(argv[1],"--vst3-probe"))return runVST3Probe(argv[2]);@autoreleasepool{
    [NSApplication sharedApplication];AURack rack;
    AUChoice au{{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple AUHipass"};rack.slots.push_back(std::make_unique<AUEffect>(au));assert(!rack.slots[0]->prepare(48000));rack.slots[0]->bypass=true;
    AURackUI* ui=[[AURackUI alloc] initWithRack:&rack];[ui show];
    __block int before=0,after=0;ui.beforeEdit=^{++before;};ui.afterEdit=^{++after;};
    VST3Choice choice{std::string(getenv("PWD"))+"/build/BOXGain.vst3","424F5854455354310102030405060708","BOX Tests: Deterministic Gain"};
    [ui addVST3Choice:choice];assert(rack.slots.size()==2&&rack.slots[1]->isVST3());assert(before==1&&after==1);
    NSArray* names=[ui valueForKey:@"labels"];assert([((NSTextField*)names[1]).stringValue hasPrefix:@"[VST3]"]);
    NSArray* presets=[ui valueForKey:@"presetButtons"];assert(!((NSButton*)presets[1]).enabled);
    // Reproduce the running app: controls() runs every tick, refreshStatus() every 0.2s.
    NSArray<NSButton*>* controls=[ui valueForKey:@"editButtons"];
    bool save=false,load=false;
    for(NSButton* control in controls){if([control.title isEqualToString:@"Save the Rack…"])save=true;if([control.title isEqualToString:@"Load the Rack…"])load=true;}
    assert(save&&load);
    NSAttributedString* stableTitle=((NSButton*)presets[1]).attributedTitle;
    for(int tick=0;tick<120;++tick){
        [ui setEditingAllowed:YES];
        for(NSButton* control in controls){BOOL browser=control.action==NSSelectorFromString(@"presets:")||control.action==NSSelectorFromString(@"previousPreset:")||control.action==NSSelectorFromString(@"nextPreset:");if(browser)assert(control.enabled==(control.tag==0));}
        if(tick%6==0)[ui refreshStatus];
        assert(!((NSButton*)presets[1]).enabled);
        assert(((NSButton*)presets[1]).attributedTitle==stableTitle);
    }
    [ui setEditingAllowed:NO];for(NSButton* control in controls)assert(!control.enabled);
    [ui setEditingAllowed:YES];assert(((NSButton*)presets[0]).enabled&&!((NSButton*)presets[1]).enabled);
    float l[8192],r[8192];std::fill_n(l,8192,2.0f);std::fill_n(r,8192,-3.0f);rack.process(l,r,8192);for(int i=0;i<8192;++i)assert(l[i]==2&&r[i]==-3);
    DSPParameters dsp;SpatialParameters spatial;
    dsp.inputDB=7.25f;dsp.masterDB=-21.5f;dsp.eqBypass=true;dsp.limiterBypass=true;
    for(int i=0;i<15;++i)dsp.bands[i]=float(i-7)*1.25f;
    spatial.enabled=true;spatial.angle=57;spatial.distance=2.25f;spatial.amount=.875f;
    [ui setDSPParameters:&dsp spatialParameters:&spatial];
    __block int settingsLoaded=0;ui.settingsDidLoad=^{++settingsLoaded;};
    NSDictionary* document=[ui rackDocument];assert([document[@"version"] isEqual:@4]);
    NSURL* file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSData* bytes=[NSPropertyListSerialization dataWithPropertyList:document format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];assert([bytes writeToURL:file atomically:YES]);
    id decoded=[NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:file] options:NSPropertyListImmutable format:nil error:nil];[NSFileManager.defaultManager removeItemAtURL:file error:nil];
    dsp.inputDB=0;dsp.masterDB=0;spatial.enabled=false;dsp.bands[2]=0;
    assert([ui restoreRackDocument:decoded]);assert(settingsLoaded==1&&rack.slots.size()==2&&rack.slots[1]->isVST3());
    assert(dsp.inputDB==7.25f&&dsp.masterDB==-21.5f&&dsp.eqBypass&&dsp.limiterBypass&&dsp.bands[2]==-6.25f);
    assert(spatial.enabled&&spatial.angle==57&&spatial.distance==2.25f&&spatial.amount==.875f);
    for(id bad in @[@{@"inputDB":@99},@{@"inputDB":@(NAN)},@{@"geq":@{@"bands":@[],@"bypass":@YES}},@{@"spatial":@{@"enabled":@YES,@"angle":@90,@"distance":@1,@"amount":@.5}}]){
        NSMutableDictionary* broken=[decoded mutableCopy];NSMutableDictionary* settings=[broken[@"settings"] mutableCopy];[settings addEntriesFromDictionary:bad];broken[@"settings"]=settings;auto* current=rack.slots[0].get();
        assert(![ui restoreRackDocument:broken]);assert(current==rack.slots[0].get()&&dsp.inputDB==7.25f&&settingsLoaded==1);
    }
    NSMutableDictionary* broken=[decoded mutableCopy];NSMutableArray* slots=[broken[@"slots"] mutableCopy];NSMutableDictionary* entry=[slots[1] mutableCopy];NSMutableDictionary* state=[entry[@"state"] mutableCopy];state[@"path"]=@"/nonexistent/BOX.vst3";entry[@"state"]=state;slots[1]=entry;broken[@"slots"]=slots;
    auto* current=rack.slots[0].get();dsp.inputDB=-3;assert(![ui restoreRackDocument:broken]);assert(current==rack.slots[0].get()&&dsp.inputDB==-3&&settingsLoaded==1);
    NSMutableDictionary* legacy=[decoded mutableCopy];legacy[@"version"]=@2;[legacy removeObjectForKey:@"settings"];assert([ui restoreRackDocument:legacy]);assert(dsp.inputDB==-3&&settingsLoaded==1);
    legacy[@"version"]=@1;legacy[@"slots"]=@[legacy[@"slots"][0]];assert([ui restoreRackDocument:legacy]);assert(dsp.inputDB==-3&&settingsLoaded==1);
    assert([ui restoreRackDocument:decoded]);assert(settingsLoaded==2&&dsp.inputDB==7.25f);
    before=after=1; // subsequent edit assertions count only their own pause/resume boundaries.
    NSButton* button=[NSButton new];button.tag=1;[ui editor:button];bool visible=false;for(NSWindow* w in NSApp.windows)if([w.title containsString:@"BOX Tests"]&&w.visible)visible=true;assert(visible);
    [ui up:button];assert(rack.slots[0]->isVST3());button.tag=0;[ui down:button];assert(rack.slots[1]->isVST3());button.tag=1;[ui editor:button];[ui remove:button];assert(rack.slots.size()==2&&!rack.slots[1]&&!rack.slots[0]->isVST3());assert(before==4&&after==4);
    auto missing=choice;missing.path+=".missing";[ui addVST3Choice:missing];assert(rack.slots.size()==2&&!rack.slots[1]&&before==4&&after==4);
    rack.slots[0]->bypass=true;assert([ui installEffect:std::make_unique<VST3Effect>(choice) atIndex:0]);assert(rack.slots.size()==2&&!rack.slots[1]&&rack.slots[0]->isVST3()&&rack.slots[0]->bypass);
    presets=[ui valueForKey:@"presetButtons"];assert(!((NSButton*)presets[0]).enabled);
    assert([ui installEffect:std::make_unique<AUEffect>(au) atIndex:0]);assert(!rack.slots[0]->isVST3()&&rack.slots[0]->bypass);assert(dsp.inputDB==7.25f);
    NSMenuItem* captured=[NSMenuItem new];captured.tag=99999;captured.representedObject=@{@"destination":@0,@"path":[NSString stringWithUTF8String:choice.path.c_str()],@"cid":[NSString stringWithUTF8String:choice.cid.c_str()],@"name":@"Captured choice"};[ui addVST3:captured];assert(rack.slots[0]->isVST3());
    [ui setValue:@YES forKey:@"vstScanRunning"];[ui setEditingAllowed:YES];bool scanDisabled=false,saveEnabled=false;
    for(NSButton* control in [ui valueForKey:@"editButtons"]){if([control.title isEqualToString:@"Scan VST3"])scanDisabled=!control.enabled;if([control.title isEqualToString:@"Save the Rack…"])saveEnabled=control.enabled;}assert(scanDisabled&&saveEnabled);
    [ui setValue:@NO forKey:@"vstScanRunning"];[ui setEditingAllowed:YES];
    [ui closeEditors];puts("PASS: mixed AU/VST3 + Gain/GEQ/Spatial file roundtrip, legacy v1/v2, invalid settings/missing plugin preserve state, stable VST3 preset disabled state across 120 running ticks, Save/Load the Rack labels, AU/VST3 mixed rack, GUI routing, host preset controls disabled, stereo/chunking/headroom, reorder/remove closes editors, failed insertion preserves rack");
}}
