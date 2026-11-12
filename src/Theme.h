#pragma once
#import <Cocoa/Cocoa.h>
#import "DrawText.h"
static inline NSColor* DARColor(unsigned rgb) {return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255. green:((rgb>>8)&255)/255. blue:(rgb&255)/255. alpha:1];}
static inline NSColor* DARNavy(){return DARColor(0x10264B);}
static inline NSColor* DARDeep(){return DARColor(0x09182F);}
static inline NSColor* DARAmber(){return DARColor(0xFFAF24);}
static inline NSColor* DARRed(){return DARColor(0xB51F35);}
@interface DARButton : NSButton
@property BOOL primary;
@end
@interface DARFaceplate : NSView
@property NSInteger slotNumber;
@property BOOL selected;
@end

@interface DARMiniMeter : NSView
@property float left;
@property float right;
@end
