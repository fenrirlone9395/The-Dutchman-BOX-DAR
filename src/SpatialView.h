#import <Cocoa/Cocoa.h>
#include "SpatialDSP.hpp"
@interface DARSpatialView : NSView
- (instancetype)initWithParameters:(SpatialParameters*)parameters;
- (void)resetField;
@end
