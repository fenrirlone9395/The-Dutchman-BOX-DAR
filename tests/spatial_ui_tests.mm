#import <Cocoa/Cocoa.h>
#import "../src/SpatialView.h"
#include <cassert>
@interface DARSpatialView (GeometryTests)
- (NSPoint)speaker:(NSInteger)side;
- (NSPoint)projectX:(double)x depth:(double)z;
@end
static NSEvent* mouse(DARSpatialView* view,NSEventType type,NSPoint point,int clicks=1){return [NSEvent mouseEventWithType:type location:[view convertPoint:point toView:nil] modifierFlags:0 timestamp:0 windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:clicks pressure:1];}
@interface TestWheel : NSObject
@property NSPoint locationInWindow;
@property CGFloat scrollingDeltaY;
@property NSEventPhase momentumPhase;
@property NSEventModifierFlags modifierFlags;
@property BOOL hasPreciseScrollingDeltas;
@end
@implementation TestWheel
@end
static void scroll(DARSpatialView* view,NSInteger side,CGFloat delta){
    TestWheel* e=[TestWheel new];e.locationInWindow=[view convertPoint:[view speaker:side] toView:nil];e.scrollingDeltaY=delta;
    [view scrollWheel:(NSEvent*)e];
}
int main(){@autoreleasepool{
    [NSApplication sharedApplication];SpatialParameters p;DARSpatialView* view=[[DARSpatialView alloc] initWithParameters:&p];
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentView=view;
    NSPoint initial=[view speaker:1];[view mouseDown:mouse(view,NSEventTypeLeftMouseDown,initial)];
    [view mouseDragged:mouse(view,NSEventTypeLeftMouseDragged,[view projectX:1.6 depth:1.2])];[view mouseUp:mouse(view,NSEventTypeLeftMouseUp,initial)];
    assert(std::abs(p.distance.load()-2)<1e-4 && std::abs(p.angle.load()-53.1301)<.01);
    NSPoint l=[view speaker:-1],r=[view speaker:1];assert(std::abs(l.x+r.x-760)<1e-5 && l.y==r.y);
    NSPoint head=[view projectX:0 depth:0];[view mouseDown:mouse(view,NSEventTypeLeftMouseDown,head)];head.y-=60;[view mouseDragged:mouse(view,NSEventTypeLeftMouseDragged,head)];assert(std::abs(p.amount.load()-.8)<1e-5);
    [view resetField];assert(p.angle==30&&p.distance==1.5&&p.amount==.5);
    scroll(view,1,1);assert(p.angle==32&&p.hrtfAngle==60);
    p.hrtf=true;scroll(view,-1,10);assert(p.hrtfAngle==75&&p.angle==32);
    [view resetField];assert(p.hrtfAngle==60&&p.angle==32);
    NSLog(@"PASS: perspective drag maps to angle/distance, symmetric speakers, listener amount drag, reset");
}}
