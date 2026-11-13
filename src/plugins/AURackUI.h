#import <Cocoa/Cocoa.h>
#include "AURack.hpp"
#include "../SpatialDSP.hpp"
@interface AURackUI : NSObject
- (instancetype)initWithRack:(AURack*)rack;
- (void)show;
- (void)rebuild;
- (NSView*)embeddedView;
@property(copy) void (^beforeEdit)(void);
@property(copy) void (^afterEdit)(void);
@property double processingRate;
- (void)setDSPParameters:(DSPParameters*)dsp spatialParameters:(SpatialParameters*)spatial;
@property(copy) void (^settingsDidLoad)(void);
// Main-thread document operations, also used by the file dialogs.
- (NSDictionary*)rackDocument;
- (BOOL)restoreRackDocument:(id)document;
- (void)setEditingAllowed:(BOOL)allowed;
- (void)refreshStatus;
- (void)closeEditors;
@end
