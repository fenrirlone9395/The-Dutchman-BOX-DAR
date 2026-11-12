#import <Cocoa/Cocoa.h>
#import "../src/plugins/AURackUI.h"
#include <cassert>
#include <iostream>
@interface AURackUI (EffectMenuTest)
- (NSMenu*)effectMenu;
- (void)addChosenEffect:(NSMenuItem*)sender;
- (void)remove:(NSButton*)sender;
@end
static NSMenuItem* findHipass(NSMenu* menu) {
    for(NSMenuItem* item in menu.itemArray){if([item.title.lowercaseString containsString:@"hipass"] && item.action==@selector(addChosenEffect:))return item;if(item.submenu){NSMenuItem* found=findHipass(item.submenu);if(found)return found;}}
    return nil;
}
int main(){@autoreleasepool{
    [NSApplication sharedApplication];AURack rack;AURackUI* ui=[[AURackUI alloc] initWithRack:&rack];[ui show];
    NSMenu* menu=[ui effectMenu];NSMenuItem* choice=findHipass(menu);assert(choice);assert(rack.slots.empty());
    __block int before=0,after=0;ui.beforeEdit=^{++before;};ui.afterEdit=^{++after;};
    for(int i=0;i<8;++i){[ui addChosenEffect:choice];assert(rack.slots.size()==size_t(i+1));assert(rack.slots.back()->error==0);}
    [ui addChosenEffect:choice];assert(rack.slots.size()==8 && before==8 && after==8);assert([ui effectMenu].itemArray[0].action==nil);
    NSWindow* host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,624) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSView* embedded=[ui embeddedView];embedded.translatesAutoresizingMaskIntoConstraints=YES;embedded.frame=host.contentView.bounds;[host.contentView addSubview:embedded];[host.contentView layoutSubtreeIfNeeded];
    NSStackView* rows=[ui valueForKey:@"rows"];NSScrollView* scroll=[ui valueForKey:@"slotScroll"];
    assert(rows.arrangedSubviews.count==8);
    [rows layoutSubtreeIfNeeded];[scroll layoutSubtreeIfNeeded];
    assert(rows.fittingSize.height<=scroll.contentSize.height+1);
    for(NSView* row in rows.arrangedSubviews)assert(row.frame.size.height==62);
    NSButton* button=[NSButton new];button.tag=3;[ui remove:button];assert(rack.slots.size()==7&&rows.arrangedSubviews.count==8);assert(findHipass([ui effectMenu]));
    NSMutableArray<NSView*>* pending=[NSMutableArray arrayWithObject:embedded];bool scan=false,save=false,load=false;
    while(pending.count){NSView* v=pending.lastObject;[pending removeLastObject];[pending addObjectsFromArray:v.subviews];assert(![v isKindOfClass:NSPopUpButton.class]);if([v isKindOfClass:NSButton.class]){NSButton* b=(NSButton*)v;assert(![b.title isEqualToString:@"+ Add Effect"]);if([b.title isEqualToString:@"Scan AU"])scan=true;if([b.title hasPrefix:@"Save AU Rack"])save=true;if([b.title hasPrefix:@"Load AU Rack"])load=true;}}
    assert(scan&&save&&load);[ui closeEditors];
    std::cout<<"PASS: grouped AU menu, selection-only insertion, 8-slot limit, eight populated rows fit, removal/re-add menu, retained Scan/Save/Load without global picker\n";
}}
