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
    NSLog(@"PASS: rack occupies >70%% width and >500pt height, responsive resize, floating EQ close/reopen");
    [ui closeEditors];
}}
