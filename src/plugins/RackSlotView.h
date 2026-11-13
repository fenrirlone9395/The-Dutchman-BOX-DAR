#pragma once
#import "../Theme.h"
FOUNDATION_EXPORT NSPasteboardType const DARRackSlotPasteboardType;
@interface DARRackSlotView : DARFaceplate <NSDraggingSource>
@property(copy) NSDictionary* dragPayload;
@property BOOL canDrag;
@property(copy) BOOL (^acceptPayload)(NSDictionary*);
@property(copy) BOOL (^movePayload)(NSDictionary*,NSInteger);
- (BOOL)trackReorder:(NSEvent*)event;
@end
@interface DARRackSlotName : NSTextField
@property(weak) DARRackSlotView* rackCard;
@property(copy) void (^activate)(void);
@end
