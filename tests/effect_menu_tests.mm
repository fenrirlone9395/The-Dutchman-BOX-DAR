#import <Cocoa/Cocoa.h>
#import "../src/plugins/AURackUI.h"
#include <cassert>
#include <iostream>
#import "../src/plugins/RackSlotView.h"
@interface AURackUI (EffectMenuTest)
- (NSMenu*)effectMenu;
- (NSMenu*)effectMenuForSlot:(NSInteger)index;
- (BOOL)moveSlotFrom:(NSInteger)source toSlot:(NSInteger)boundary;
- (BOOL)acceptDragPayload:(NSDictionary*)payload;
- (BOOL)installEffect:(std::unique_ptr<RackEffect>)slot atIndex:(NSInteger)index;
- (void)addChosenEffect:(NSMenuItem*)sender;
- (void)remove:(NSButton*)sender;
@end
@interface TestRackDrop : NSObject
@property(strong) NSPasteboard* draggingPasteboard;
@property NSPoint draggingLocation;
@end
@implementation TestRackDrop
@end
static NSMenuItem* findHipass(NSMenu* menu) {
    for(NSMenuItem* item in menu.itemArray){if([item.title.lowercaseString containsString:@"hipass"] && item.action==@selector(addChosenEffect:))return item;if(item.submenu){NSMenuItem* found=findHipass(item.submenu);if(found)return found;}}
    return nil;
}
int main(){@autoreleasepool{
 [NSApplication sharedApplication];AURack rack;AURackUI* ui=[[AURackUI alloc] initWithRack:&rack];[ui show];
 NSMenuItem* choice=findHipass([ui effectMenuForSlot:4]);assert(choice);[ui addChosenEffect:choice];
 assert(rack.slots.size()==5&&!rack.slots[0]&&rack.slots[4]);auto* effect=rack.slots[4].get();effect->bypass=true;
 assert([ui moveSlotFrom:4 toSlot:1]);assert(!rack.slots[4]&&rack.slots[1].get()==effect&&effect->bypass);
 NSDictionary* saved=[ui rackDocument];assert([saved[@"version"] isEqual:@4]);assert([saved[@"slots"][0][@"empty"] boolValue]);
 assert([ui restoreRackDocument:saved]);assert(!rack.slots[0]&&rack.slots[1]&&!rack.slots[4]);
 choice=findHipass([ui effectMenuForSlot:7]);[ui addChosenEffect:choice];auto* last=rack.slots[7].get();auto* second=rack.slots[1].get();
 assert([ui moveSlotFrom:1 toSlot:7]);assert(rack.slots[1].get()==last&&rack.slots[7].get()==second);
 NSStackView* rows=[ui valueForKey:@"rows"];DARRackSlotView* source=(DARRackSlotView*)rows.arrangedSubviews[7];DARRackSlotView* dest=(DARRackSlotView*)rows.arrangedSubviews[3];
 TestRackDrop* drop=[TestRackDrop new];drop.draggingPasteboard=[NSPasteboard pasteboardWithUniqueName];[drop.draggingPasteboard declareTypes:@[DARRackSlotPasteboardType] owner:nil];[drop.draggingPasteboard setPropertyList:source.dragPayload forType:DARRackSlotPasteboardType];drop.draggingLocation=[dest convertPoint:NSMakePoint(30,5) toView:nil];
 assert([dest draggingEntered:(id<NSDraggingInfo>)drop]==NSDragOperationMove);assert([dest performDragOperation:(id<NSDraggingInfo>)drop]);assert(rack.slots[3].get()==second&&!rack.slots[7]);
 NSButton* button=[NSButton new];button.tag=3;[ui remove:button];assert(!rack.slots[3]&&rack.slots[1].get()==last);
 float l[32],r[32];std::fill_n(l,32,.25f);std::fill_n(r,32,-.25f);rack.slots[1]->bypass=true;rack.prepare(48000);rack.process(l,r,32);assert(l[0]==.25f&&r[0]==-.25f);
 [ui setEditingAllowed:NO];assert(![ui moveSlotFrom:1 toSlot:6]);[ui setEditingAllowed:YES];
 NSMutableDictionary* legacy=[saved mutableCopy];legacy[@"version"]=@1;legacy[@"slots"]=@[saved[@"slots"][1]];assert([ui restoreRackDocument:legacy]);assert(rack.slots[0]);
 [ui closeEditors];std::cout<<"PASS: chosen empty position, occupied/empty swap, occupied swap, native empty drop, deletion preserves holes, v4 roundtrip, legacy load, null-safe audio, editing gate\n";
}}
