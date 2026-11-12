#import <Cocoa/Cocoa.h>
#include "DSP.hpp"
@interface DARGraphicEQ : NSControl
@property BOOL compact;
- (instancetype)initWithParameters:(DSPParameters*)parameters;
- (void)flatten;
@property double sampleRate;
@end
@interface DARGainKnob : NSControl
@property float minimum;
@property float maximum;
@property(copy) NSString* caption;
@end
