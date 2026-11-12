#import <Cocoa/Cocoa.h>
#import "../src/RackControls.h"
#include <cassert>
@interface Receiver : NSObject
@property float received;
- (void)change:(DARGainKnob*)sender;
@end
@implementation Receiver
- (void)change:(DARGainKnob*)sender {self.received=sender.floatValue;}
@end
int main(){@autoreleasepool{
    [NSApplication sharedApplication];
    DARGainKnob* knob=[[DARGainKnob alloc] initWithFrame:NSMakeRect(0,0,122,116)];knob.minimum=-60;knob.maximum=6;
    Receiver* receiver=[Receiver new];knob.target=receiver;knob.action=@selector(change:);knob.tag=4;
    knob.floatValue=-12;[knob sendAction:knob.action to:knob.target];assert(receiver.received==-12&&knob.tag==4);
    knob.floatValue=100;assert(knob.floatValue==6);
    DSPParameters params;params.bands[3]=6;DARGraphicEQ* eq=[[DARGraphicEQ alloc] initWithParameters:&params];[eq flatten];assert(params.bands[3]==0);
    NSLog(@"PASS: knob action/value/range/tag and GEQ Flat");
}}
