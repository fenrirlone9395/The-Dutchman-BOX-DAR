#define main DutchmanApplicationMain
#include "../src/Main.mm"
#undef main
#include <cassert>
int main(){@autoreleasepool{
    [NSApplication sharedApplication];RackApp* app=[RackApp new];[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    NSWindow* mainWindow=[app valueForKey:@"window"];AURackUI* ui=[app valueForKey:@"auUI"];
    NSView* rack=[ui embeddedView];
    [mainWindow.contentView layoutSubtreeIfNeeded];assert(rack.frame.size.width/mainWindow.contentView.bounds.size.width>.70);assert(rack.frame.size.height>500);
    CGFloat oldWidth=rack.frame.size.width;
    [mainWindow setContentSize:NSMakeSize(1280,860)];mainWindow.contentView.needsLayout=YES;[mainWindow.contentView layoutSubtreeIfNeeded];assert(rack.frame.size.width>oldWidth);
    [app showEQ:nil];NSPanel* eq=[app valueForKey:@"eqPanel"];assert(eq.visible&&eq.level==NSFloatingWindowLevel);assert([[app valueForKey:@"geq"] isKindOfClass:DARGraphicEQ.class]);
    [eq close];[app showEQ:nil];assert(eq.visible);
    NSMutableArray<NSView*>* pending=[NSMutableArray arrayWithObject:mainWindow.contentView];int knobs=0;bool input=false,output=false;
    while(pending.count){NSView* v=pending.lastObject;[pending removeLastObject];[pending addObjectsFromArray:v.subviews];if([v isKindOfClass:DARGainKnob.class]){DARGainKnob* k=(DARGainKnob*)v;++knobs;assert(k.target==app && k.action==@selector(gainKnob:));if(k.tag==0)input=true;if(k.tag==1)output=true;}}
    assert(knobs==2 && input && output);
    [app showSpatial:nil];NSPanel* spatial=[app valueForKey:@"spatialPanel"];DARSpatialView* field=[app valueForKey:@"spatialView"];
    assert(spatial.visible && spatial.level==NSFloatingWindowLevel && field);[spatial close];[app showSpatial:nil];assert(spatial.visible);
    NSLog(@"PASS: rack occupies >70%% width and >500pt height, responsive resize, floating EQ and Spatial close/reopen");
    // Exercise the installed menu after launch, rather than calling the action directly.
    NSMenu* commands=NSApp.mainMenu.itemArray.firstObject.submenu;
    NSInteger diagnosticItem=[commands indexOfItemWithTarget:app andAction:@selector(showDiagnostics:)];
    NSInteger legacyItem=[commands indexOfItemWithTarget:app andAction:@selector(selectLegacy:)];
    assert(diagnosticItem>=0 && legacyItem>=0);
    NSMenuItem* shortcut=[commands itemAtIndex:diagnosticItem];assert([shortcut.keyEquivalent isEqualToString:@"d"]);
    assert(shortcut.keyEquivalentModifierMask==(NSEventModifierFlagCommand|NSEventModifierFlagOption));
    [commands performActionForItemAtIndex:diagnosticItem];NSPanel* diagnostic=[app valueForKey:@"diagnosticsPanel"];NSTextView* text=[app valueForKey:@"diagnosticsText"];assert(diagnostic.visible && text.string.length>0);assert(![[app valueForKey:@"legacyRateRequested"] boolValue]);
    NSMenuItem* legacy=[commands itemAtIndex:legacyItem];assert(legacy.state==NSControlStateValueOff);
    [commands performActionForItemAtIndex:legacyItem];assert([[app valueForKey:@"legacyRateRequested"] boolValue] && legacy.state==NSControlStateValueOn);
    [commands performActionForItemAtIndex:legacyItem];assert(![[app valueForKey:@"legacyRateRequested"] boolValue] && legacy.state==NSControlStateValueOff);
    NSLog(@"PASS: installed Diagnostics menu action/shortcut and Legacy checkbox toggle survive launch");
    [ui closeEditors];
}}
