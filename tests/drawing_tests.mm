#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../src/DrawText.h"
#import "../src/MeterView.h"
#import "../src/RackControls.h"
#include "../src/plugins/AURack.hpp"
#include <cassert>
#include <limits>
#include <iostream>
static id unavailableFont(id,SEL,CGFloat,NSFontWeight){return nil;}
static id unavailableSystemFont(id,SEL,CGFloat){return nil;}
@interface DARMeterView (Regression)
- (void)text:(NSString*)text x:(CGFloat)x y:(CGFloat)y color:(NSColor*)color size:(CGFloat)size;
@end
int main(){@autoreleasepool{
    [NSApplication sharedApplication];
    DARMeterView* meter=[[DARMeterView alloc] initWithTitle:@"INPUT"];
    meter.frame=NSMakeRect(0,0,560,154);
    DSPParameters parameters;
    DARGraphicEQ* eq=[[DARGraphicEQ alloc] initWithParameters:&parameters];eq.frame=NSMakeRect(0,0,1120,240);
    NSBitmapImageRep* bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:1200 pixelsHigh:300 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    Method mono=class_getClassMethod(NSFont.class,@selector(monospacedSystemFontOfSize:weight:));
    IMP original=method_setImplementation(mono,(IMP)unavailableFont);
    assert(DARTextAttributes(11,nil)[NSFontAttributeName]); // System font fallback.
    Method system=class_getClassMethod(NSFont.class,@selector(systemFontOfSize:));
    Method fixed=class_getClassMethod(NSFont.class,@selector(userFixedPitchFontOfSize:));
    IMP oldSystem=method_setImplementation(system,(IMP)unavailableSystemFont);
    IMP oldFixed=method_setImplementation(fixed,(IMP)unavailableSystemFont);
    // Even total font lookup failure must not construct a dictionary containing nil.
    assert(!DARTextAttributes(11,nil)[NSFontAttributeName]);
    method_setImplementation(system,oldSystem);method_setImplementation(fixed,oldFixed);
    [meter text:@"fallback" x:0 y:0 color:nil size:std::numeric_limits<double>::quiet_NaN()];
    [meter drawRect:meter.bounds];[eq drawRect:eq.bounds];
    method_setImplementation(mono,original);
    for(int i=0;i<20;++i) {
        AUEffect effect({{kAudioUnitType_Effect,kAudioUnitSubType_HighPassFilter,kAudioUnitManufacturer_Apple,0,0},"Apple AUHipass"});
        assert(effect.prepare(48000)==0);
        [meter updateLeft:.2 right:.4 time:i*.1];[meter drawRect:meter.bounds];[eq drawRect:eq.bounds];
    }
    [NSGraphicsContext restoreGraphicsState];
    std::cout<<"PASS: nil font/color fallback, all font lookups unavailable, invalid font size, meter/GEQ redraw after 20 AU loads\n";
}}
