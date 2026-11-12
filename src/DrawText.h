#pragma once
#import <Cocoa/Cocoa.h>
#include <cmath>
// AppKit may fail to resolve a font. Never put a nullable result in a dictionary literal.
static inline NSDictionary<NSAttributedStringKey,id>* DARTextAttributes(CGFloat size,NSColor* color) {
    if(!std::isfinite(size) || size<=0) size=11;
    NSFont* font=[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightMedium];
    if(!font) font=[NSFont systemFontOfSize:size];
    if(!font) font=[NSFont userFixedPitchFontOfSize:size];
    NSMutableDictionary* attributes=[NSMutableDictionary new];
    if(font) attributes[NSFontAttributeName]=font;
    NSColor* ink=color?:NSColor.textColor;
    if(ink) attributes[NSForegroundColorAttributeName]=ink;
    return attributes;
}
static inline void DARDrawText(NSString* text,NSPoint point,CGFloat size,NSColor* color) {
    if(!text.length) return;
    [text drawAtPoint:point withAttributes:DARTextAttributes(size,color)];
}
