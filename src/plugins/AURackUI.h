#import <Cocoa/Cocoa.h>
#include "AURack.hpp"
@interface AURackUI : NSObject
- (instancetype)initWithRack:(AURack*)rack;
- (void)show;
- (void)rebuild;
- (NSView*)embeddedView;
@property(copy) void (^beforeEdit)(void);
@property(copy) void (^afterEdit)(void);
@property double processingRate;
- (void)setEditingAllowed:(BOOL)allowed;
- (void)refreshStatus;
- (void)closeEditors;
@end
