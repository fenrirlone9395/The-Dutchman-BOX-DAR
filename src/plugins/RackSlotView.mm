#import "RackSlotView.h"
NSPasteboardType const DARRackSlotPasteboardType=@"local.dutchman.rack-slot";
@implementation DARRackSlotView {
    BOOL dropVisible,dropAfter;
    DARRackSlotView* activeDragSource; // Keep the source alive if the drop rebuilds all rows.
}
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame]))[self registerForDraggedTypes:@[DARRackSlotPasteboardType]];
    return self;
}
- (BOOL)trackReorder:(NSEvent*)event {
    if(!self.canDrag)return NO;
    for(;;){
        NSEvent* next=[self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
        if(!next||next.type==NSEventTypeLeftMouseUp)return NO;
        if(hypot(next.locationInWindow.x-event.locationInWindow.x,next.locationInWindow.y-event.locationInWindow.y)<4)continue;
        NSPasteboardItem* payload=[NSPasteboardItem new];[payload setPropertyList:self.dragPayload forType:DARRackSlotPasteboardType];
        NSDraggingItem* item=[[NSDraggingItem alloc] initWithPasteboardWriter:payload];
        NSBitmapImageRep* bitmap=[self bitmapImageRepForCachingDisplayInRect:self.bounds];[self cacheDisplayInRect:self.bounds toBitmapImageRep:bitmap];
        NSImage* image=[[NSImage alloc] initWithSize:self.bounds.size];[image addRepresentation:bitmap];[item setDraggingFrame:self.bounds contents:image];
        activeDragSource=self;
        [self beginDraggingSessionWithItems:@[item] event:next source:self];return YES;
    }
}
- (void)mouseDown:(NSEvent*)event { [self trackReorder:event]; }
- (void)draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {activeDragSource=nil;}
- (void)resetCursorRects {if(self.canDrag)[self addCursorRect:NSMakeRect(0,0,64,self.bounds.size.height) cursor:NSCursor.openHandCursor];}
- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {return context==NSDraggingContextWithinApplication?NSDragOperationMove:NSDragOperationNone;}
- (NSDictionary*)payload:(id<NSDraggingInfo>)sender {
    id payload=[sender.draggingPasteboard propertyListForType:DARRackSlotPasteboardType];
    return [payload isKindOfClass:NSDictionary.class]?payload:nil;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSDictionary* payload=[self payload:sender];BOOL accepted=payload&&self.acceptPayload&&self.acceptPayload(payload);
    dropVisible=accepted;dropAfter=[self convertPoint:sender.draggingLocation fromView:nil].y>self.bounds.size.height/2;self.needsDisplay=YES;
    return accepted?NSDragOperationMove:NSDragOperationNone;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {return [self draggingUpdated:sender];}
- (void)draggingExited:(id<NSDraggingInfo>)sender {dropVisible=NO;self.needsDisplay=YES;}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {return [self draggingUpdated:sender]==NSDragOperationMove;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSDictionary* payload=[self payload:sender];BOOL accepted=payload&&self.acceptPayload&&self.acceptPayload(payload);
    NSInteger boundary=self.slotNumber-1;
    dropVisible=NO;self.needsDisplay=YES;
    return accepted&&self.movePayload&&self.movePayload(payload,boundary);
}
- (void)drawRect:(NSRect)rect {
    [super drawRect:rect];if(dropVisible){[DARAmber() setFill];NSFrameRectWithWidth(NSInsetRect(self.bounds,2,2),2);}
}
@end
@implementation DARRackSlotName
- (void)resetCursorRects {[self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];}
- (void)mouseDown:(NSEvent*)event {if(![self.rackCard trackReorder:event]&&self.activate)self.activate();}
- (BOOL)accessibilityPerformPress {if(self.activate){self.activate();return YES;}return NO;}
@end
