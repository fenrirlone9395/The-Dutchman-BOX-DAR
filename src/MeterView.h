#import <Cocoa/Cocoa.h>
@interface DARMeterView : NSView
@property BOOL vertical;
- (instancetype)initWithTitle:(NSString*)title;
- (void)updateLeft:(float)left right:(float)right time:(double)now;
- (void)clearHold;
@end
