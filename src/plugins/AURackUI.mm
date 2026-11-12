#import "AURackUI.h"
#import <CoreAudioKit/CoreAudioKit.h>
#import "../DrawText.h"
#import "../Theme.h"
#import <AudioToolbox/AUCocoaUIView.h>
@implementation AURackUI {
    AURack* rack;
    std::vector<AUChoice> choices;
    NSWindow* window;
    NSStackView* rows;
    NSTextField* info;
    NSMutableArray<NSButton*>* editButtons;
    NSMutableArray<NSTextField*>* labels;
    NSMutableDictionary<NSNumber*,NSWindow*>* editors;
    NSMutableDictionary<NSNumber*,id>* factories;
    NSMutableDictionary<NSNumber*,id>* sizeObservers;
    NSMutableArray<NSButton*>* presetButtons;
    NSMutableDictionary<NSValue*,NSArray<NSDictionary*>*>* presetLists;
    NSMutableArray<DARFaceplate*>* cards;
    NSMutableArray<DARMiniMeter*>* miniMeters;
    AUEffect* selectedSlot;
    NSScrollView* slotScroll;
    BOOL editable;
    NSView* embedded;
    NSLayoutConstraint* embeddedHeight;
}
- (NSButton*)button:(NSString*)title action:(SEL)action tag:(NSInteger)tag editing:(BOOL)editing {
    DARButton* b=[DARButton buttonWithTitle:title target:self action:action];b.primary=[title isEqualToString:@"+ Add Effect"]; b.tag=tag;
    if(editing) { [editButtons addObject:b]; b.enabled=editable; } return b;
}
- (instancetype)initWithRack:(AURack*)value {
    if((self=[super init])) { cards=[NSMutableArray new];miniMeters=[NSMutableArray new];presetButtons=[NSMutableArray new];presetLists=[NSMutableDictionary new];sizeObservers=[NSMutableDictionary new]; rack=value; self.processingRate=48000; editable=YES; editors=[NSMutableDictionary new]; factories=[NSMutableDictionary new]; editButtons=[NSMutableArray new]; labels=[NSMutableArray new]; }
    return self;
}
- (void)show {
    if(!window) {
        window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,820,520) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO; window.title=@"The Dutchman BOX/DAR — Audio Units Rack";
        window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSStackView* root=[NSStackView stackViewWithViews:@[]]; root.orientation=NSUserInterfaceLayoutOrientationVertical; root.alignment=NSLayoutAttributeLeading; root.spacing=6; root.translatesAutoresizingMaskIntoConstraints=NO;
        [window.contentView addSubview:root];
        [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:8],[root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-8],[root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:8]]];

        [root addArrangedSubview:[NSStackView stackViewWithViews:@[[self button:@"Scan AU" action:@selector(scan:) tag:0 editing:YES],[self button:@"Save AU Rack…" action:@selector(save:) tag:0 editing:YES],[self button:@"Load AU Rack…" action:@selector(load:) tag:0 editing:YES]]]];
        rows=[NSStackView stackViewWithViews:@[]]; rows.orientation=NSUserInterfaceLayoutOrientationVertical; rows.alignment=NSLayoutAttributeLeading; rows.spacing=6;
        slotScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,760,100)];slotScroll.hasVerticalScroller=YES;slotScroll.drawsBackground=YES;slotScroll.backgroundColor=DARDeep();slotScroll.autohidesScrollers=YES;slotScroll.documentView=rows;rows.autoresizingMask=NSViewWidthSizable;
        [root addArrangedSubview:slotScroll];[slotScroll.bottomAnchor constraintEqualToAnchor:root.superview.bottomAnchor constant:-32].active=YES;[slotScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
        info=[NSTextField wrappingLabelWithString:@"再生中もRackを変更できます。変更時は処理出力を短く休止します。"];
        [root addArrangedSubview:info]; [info.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
        if(editable) [self scan:nil]; [self rebuild]; [window center];
    }
    [window makeKeyAndOrderFront:nil];
}
- (NSView*)embeddedView {
    if(!embedded) { [self show]; [window orderOut:nil]; embedded=window.contentView; window.contentView=[NSView new]; embedded.translatesAutoresizingMaskIntoConstraints=NO; embeddedHeight=[embedded.heightAnchor constraintEqualToConstant:230]; embeddedHeight.active=NO; }
    return embedded;
}
- (void)setEditingAllowed:(BOOL)allowed { editable=allowed; for(NSButton* b in editButtons) b.enabled=allowed; }
- (void)scan:(id)sender {
    if(!editable) return;
    choices=scanAUEffects();
    info.stringValue=[NSString stringWithFormat:@"%zu AUv2 Effect候補。Stereo対応は追加時に検証します。",choices.size()];
}
- (NSMenu*)effectMenu {
    NSMenu* menu=[NSMenu new];
    if(!editable || rack->slots.size()>=AURack::maximumSlots || choices.empty()) {
        NSString* title=rack->slots.size()>=AURack::maximumSlots?@"Rack is full (8/8)":@"AUがありません。Scan AUを実行してください。";
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];item.enabled=NO;[menu addItem:item];return menu;
    }
    NSMutableDictionary<NSString*,NSMenu*>* manufacturers=[NSMutableDictionary new];
    for(size_t i=0;i<choices.size();++i) {
        NSString* name=[NSString stringWithUTF8String:choices[i].name.c_str()];NSRange separator=[name rangeOfString:@":"];
        NSString* maker=separator.location==NSNotFound?@"Audio Units":[name substringToIndex:separator.location];
        NSMenu* group=manufacturers[maker];
        if(!group){group=[NSMenu new];manufacturers[maker]=group;NSMenuItem* parent=[[NSMenuItem alloc] initWithTitle:maker action:nil keyEquivalent:@""];parent.submenu=group;[menu addItem:parent];}
        NSString* title=separator.location==NSNotFound?name:[[name substringFromIndex:separator.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:@selector(addChosenEffect:) keyEquivalent:@""];item.target=self;item.tag=i;[group addItem:item];
    }
    return menu;
}
- (void)add:(NSButton*)sender {
    if(!editable || rack->slots.size()>=AURack::maximumSlots)return;
    [[self effectMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,sender.bounds.size.height) inView:sender];
}
- (void)addChosenEffect:(NSMenuItem*)sender {
    if(!editable || rack->slots.size()>=AURack::maximumSlots || sender.tag<0 || sender.tag>=NSInteger(choices.size()))return;
    auto slot=std::make_unique<AUEffect>(choices[sender.tag]);slot->prepare(self.processingRate);selectedSlot=slot.get();
    if(self.beforeEdit)self.beforeEdit();rack->slots.push_back(std::move(slot));if(self.afterEdit)self.afterEdit();[self rebuild];
}
- (void)rebuild {
    while(editButtons.count>3) [editButtons removeLastObject];
    for(NSView* row in [rows.arrangedSubviews copy]) { [rows removeArrangedSubview:row]; [row removeFromSuperview]; }
    [labels removeAllObjects];[presetButtons removeAllObjects];[cards removeAllObjects];[miniMeters removeAllObjects];
    for(size_t i=0;i<AURack::maximumSlots;++i) {
        DARFaceplate* card=[DARFaceplate new];card.slotNumber=i+1;card.translatesAutoresizingMaskIntoConstraints=NO;[rows addArrangedSubview:card];
        [card.heightAnchor constraintEqualToConstant:62].active=YES;
        [card.widthAnchor constraintEqualToAnchor:slotScroll.contentView.widthAnchor constant:-12].active=YES;
        if(i>=rack->slots.size()) {
            NSButton* add=[self button:@"+ Add an effect" action:@selector(add:) tag:i editing:YES];add.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:add];
            [NSLayoutConstraint activateConstraints:@[[add.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:70],[add.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],[add.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],[add.heightAnchor constraintEqualToConstant:30]]];continue;
        }
        [cards addObject:card];
        NSTextField* name=[NSTextField labelWithString:@""];name.font=[NSFont boldSystemFontOfSize:14];name.lineBreakMode=NSLineBreakByTruncatingTail;[labels addObject:name];
        NSButton* bypass=[NSButton checkboxWithTitle:@"Bypass" target:self action:@selector(bypass:)];bypass.tag=i;bypass.state=rack->slots[i]->bypass?NSControlStateValueOn:NSControlStateValueOff;
        DARMiniMeter* meter=[DARMiniMeter new];[meter.widthAnchor constraintEqualToConstant:70].active=YES;[meter.heightAnchor constraintEqualToConstant:26].active=YES;[miniMeters addObject:meter];
        NSStackView* controls=[NSStackView stackViewWithViews:@[name,meter,bypass,[self button:@"Editor ↗" action:@selector(editor:) tag:i editing:NO],[self button:@"↑" action:@selector(up:) tag:i editing:YES],[self button:@"↓" action:@selector(down:) tag:i editing:YES],[self button:@"×" action:@selector(remove:) tag:i editing:YES]]];controls.spacing=6;controls.distribution=NSStackViewDistributionFill;[name setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];[name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSButton* preset=[self button:@"Preset: 未選択" action:@selector(presets:) tag:i editing:YES];preset.alignment=NSTextAlignmentLeft;[presetButtons addObject:preset];
        NSStackView* browser=[NSStackView stackViewWithViews:@[[self button:@"−" action:@selector(previousPreset:) tag:i editing:YES],preset,[self button:@"+" action:@selector(nextPreset:) tag:i editing:YES]]];browser.spacing=6;browser.distribution=NSStackViewDistributionFill;[preset setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        for(NSView* bar in @[controls,browser]){bar.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:bar];[bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:70].active=YES;[bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active=YES;}
        [controls.topAnchor constraintEqualToAnchor:card.topAnchor constant:4].active=YES;[controls.heightAnchor constraintEqualToConstant:24].active=YES;[browser.topAnchor constraintEqualToAnchor:card.topAnchor constant:32].active=YES;[browser.heightAnchor constraintEqualToConstant:24].active=YES;
    }
    [rows setFrameSize:NSMakeSize(MAX(700,slotScroll.contentSize.width),MAX(1,rows.fittingSize.height))];
    [self refreshStatus];
}
- (void)closeEditors { for(id token in sizeObservers.allValues) [NSNotificationCenter.defaultCenter removeObserver:token]; [sizeObservers removeAllObjects]; for(NSWindow* w in editors.allValues) { [w close]; w.contentView=nil; } [editors removeAllObjects]; [factories removeAllObjects]; }
- (void)remove:(NSButton*)sender { if(!editable) return; [presetLists removeObjectForKey:[NSValue valueWithPointer:rack->slots[sender.tag].get()]]; if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; rack->slots.erase(rack->slots.begin()+sender.tag); if(self.afterEdit) self.afterEdit(); [self rebuild]; }
- (void)up:(NSButton*)sender { if(!editable || sender.tag==0) return; if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; std::swap(rack->slots[sender.tag],rack->slots[sender.tag-1]); if(self.afterEdit) self.afterEdit(); [self rebuild]; }
- (void)down:(NSButton*)sender { if(!editable || sender.tag+1>=NSInteger(rack->slots.size())) return; if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; std::swap(rack->slots[sender.tag],rack->slots[sender.tag+1]); if(self.afterEdit) self.afterEdit(); [self rebuild]; }
- (void)bypass:(NSButton*)sender { rack->slots[sender.tag]->bypass=sender.state==NSControlStateValueOn; }
- (void)refreshStatus {
    if(!window) return;
    double total=0; BOOL unknown=NO;
    for(size_t i=0;i<rack->slots.size();++i) {
        auto& slot=*rack->slots[i]; double latency=slot.latency();
        if(!slot.bypass && !slot.error) { if(latency<0) unknown=YES; else total+=latency; }
        NSString* suffix=slot.error ? [NSString stringWithFormat:@"ERROR %d / dry",slot.error.load()] : (latency<0?@"latency ?":[NSString stringWithFormat:@"%.2f ms",latency*1000]);
        labels[i].stringValue=[NSString stringWithFormat:@"%@ · %@",[NSString stringWithUTF8String:slot.choice.name.c_str()],suffix];
        labels[i].toolTip=labels[i].stringValue;
        cards[i].selected=selectedSlot==&slot;cards[i].needsDisplay=YES;
        miniMeters[i].left=slot.outputMeter.peaks[0].exchange(0);miniMeters[i].right=slot.outputMeter.peaks[1].exchange(0);miniMeters[i].needsDisplay=YES;
        slot.refreshPresetModified();
        NSString* presetName=slot.presetName.empty()?@"未選択":[NSString stringWithUTF8String:slot.presetName.c_str()];
        NSString* title=[NSString stringWithFormat:@"%@%@",presetName,slot.presetModified?@" *":@""];
        NSMutableDictionary* attributes=[DARTextAttributes(11,NSColor.labelColor) mutableCopy];
        NSFont* font=attributes[NSFontAttributeName];
        if(slot.presetModified && font) { NSFont* italic=[NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSItalicFontMask];if(italic)attributes[NSFontAttributeName]=italic; }
        presetButtons[i].attributedTitle=[[NSAttributedString alloc] initWithString:title attributes:attributes];presetButtons[i].toolTip=title;
        NSWindow* editor=editors[@(i)];if(editor)editor.title=[NSString stringWithFormat:@"%@ — %@",[NSString stringWithUTF8String:slot.choice.name.c_str()],title];
    }
    NSString* latencyTitle=[NSString stringWithFormat:@"AU Rack — Reported latency %.2f ms%@",total*1000,unknown?@" + unknown":@""];
    window.title=latencyTitle; info.toolTip=latencyTitle;
}
- (void)editor:(NSButton*)sender {
    selectedSlot=rack->slots[sender.tag].get();[self refreshStatus];
    auto& slot=*rack->slots[sender.tag]; AudioUnit unit=slot.handle(); if(!unit || slot.error) return;
    NSNumber* key=@(sender.tag); if(editors[key]) { [editors[key] makeKeyAndOrderFront:nil]; return; }
    NSView* view=nil; UInt32 size=0; Boolean writable=false;
    if(!AudioUnitGetPropertyInfo(unit,kAudioUnitProperty_CocoaUI,kAudioUnitScope_Global,0,&size,&writable) && size>=sizeof(AudioUnitCocoaViewInfo) && size<1024*1024) {
        std::vector<unsigned char> storage(size); auto* cocoa=reinterpret_cast<AudioUnitCocoaViewInfo*>(storage.data());
        if(!AudioUnitGetProperty(unit,kAudioUnitProperty_CocoaUI,kAudioUnitScope_Global,0,cocoa,&size)) {
            NSBundle* bundle=[NSBundle bundleWithURL:(__bridge NSURL*)cocoa->mCocoaAUViewBundleLocation];
            if([bundle load]) {
                Class factoryClass=[bundle classNamed:(__bridge NSString*)cocoa->mCocoaAUViewClass[0]];
                if([factoryClass conformsToProtocol:@protocol(AUCocoaUIBase)]) {
                    id<AUCocoaUIBase> factory=[[factoryClass alloc] init];
                    view=[factory uiViewForAudioUnit:unit withSize:NSZeroSize]; if(view) factories[key]=factory;
                }
            }
            if(cocoa->mCocoaAUViewBundleLocation) CFRelease(cocoa->mCocoaAUViewBundleLocation);
            size_t count=(size-sizeof(CFURLRef))/sizeof(CFStringRef);
            for(size_t i=0;i<count;++i) if(cocoa->mCocoaAUViewClass[i]) CFRelease(cocoa->mCocoaAUViewClass[i]);
        }
    }
    BOOL generic=!view; if(!view) view=[[AUGenericView alloc] initWithAudioUnit:unit];
    if(!view) { info.stringValue=@"エディタを作成できませんでした。"; return; }
    NSSize dimensions=view.fittingSize;
    dimensions.width=MAX(dimensions.width,view.frame.size.width); dimensions.height=MAX(dimensions.height,view.frame.size.height);
    if(dimensions.width<100 || dimensions.height<100) dimensions=NSMakeSize(600,400);
    view.frame=NSMakeRect(0,0,dimensions.width,dimensions.height);
    view.autoresizingMask=NSViewNotSizable;
    NSPanel* editor=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,dimensions.width,dimensions.height) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    editor.floatingPanel=YES; editor.level=NSFloatingWindowLevel; editor.hidesOnDeactivate=YES;
    editor.releasedWhenClosed=NO; editor.title=[NSString stringWithFormat:@"%@%@",[NSString stringWithUTF8String:slot.choice.name.c_str()],generic?@" — Generic Controls":@""];
    NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,dimensions.width,dimensions.height)];
    scroll.hasVerticalScroller=YES; scroll.hasHorizontalScroller=YES; scroll.autohidesScrollers=YES;
    scroll.documentView=view; editor.contentView=scroll; editors[key]=editor;
    __weak NSWindow* weakWindow=editor; __weak NSView* weakView=view;
    void (^fit)(void)=^{
        NSWindow* w=weakWindow; NSView* v=weakView; if(!w || !v) return;
        NSRect screen=(w.screen?:NSScreen.mainScreen).visibleFrame;
        NSSize wanted=v.frame.size;
        wanted.width=MIN(MAX(wanted.width,100),screen.size.width-40);
        wanted.height=MIN(MAX(wanted.height,100),screen.size.height-80);
        [w setContentSize:wanted];
        NSRect f=w.frame; f.origin.x=MAX(screen.origin.x,MIN(f.origin.x,NSMaxX(screen)-f.size.width)); f.origin.y=MAX(screen.origin.y,MIN(f.origin.y,NSMaxY(screen)-f.size.height));
        [w setFrame:f display:YES];
        NSScrollView* sv=(NSScrollView*)w.contentView;
        [sv.documentView scrollPoint:NSMakePoint(0,sv.documentView.isFlipped?0:MAX(0,v.frame.size.height-sv.contentSize.height))];
    };
    view.postsFrameChangedNotifications=YES;
    sizeObservers[key]=[NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:view queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note){fit();}];
    fit(); [editor center]; [editor makeKeyAndOrderFront:nil];

}
- (BOOL)state:(id)state matches:(AUEffect*)slot {
    auto d=slot->choice.description;
    return [state isKindOfClass:NSDictionary.class] && [state[@"type"] isKindOfClass:NSNumber.class] && [state[@"type"] unsignedIntValue]==d.componentType && [state[@"subtype"] isKindOfClass:NSNumber.class] && [state[@"subtype"] unsignedIntValue]==d.componentSubType && [state[@"manufacturer"] isKindOfClass:NSNumber.class] && [state[@"manufacturer"] unsignedIntValue]==d.componentManufacturer;
}
- (NSArray<NSURL*>*)installedPresets:(AUEffect*)slot {
    NSMutableArray<NSURL*>* found=[NSMutableArray new];
    NSArray* roots=@[@"/Library/Audio/Presets",[@"~/Library/Audio/Presets" stringByExpandingTildeInPath]];
    for(NSString* path in roots) {
        NSDirectoryEnumerator* files=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        for(NSURL* url in files) {
            if(![url.pathExtension.lowercaseString isEqualToString:@"aupreset"])continue;
            NSNumber* size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];if(!size || size.unsignedLongLongValue>8*1024*1024)continue;
            NSData* data=[NSData dataWithContentsOfURL:url];id state=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;
            if([self state:state matches:slot])[found addObject:url];
        }
    }
    return [found sortedArrayUsingComparator:^NSComparisonResult(NSURL* a,NSURL* b){return [a.path localizedStandardCompare:b.path];}];
}
- (void)applyPresetURL:(NSURL*)url index:(NSInteger)index {
    if(!editable || index<0 || index>=NSInteger(rack->slots.size()))return;
    auto* slot=rack->slots[index].get();selectedSlot=slot;
    NSData* data=[NSData dataWithContentsOfURL:url];id state=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;
    if(![self state:state matches:slot]) {info.stringValue=@"このAU用の.aupresetファイルを選択してください。";return;}
    if(self.beforeEdit)self.beforeEdit();OSStatus s=slot->restore((__bridge CFPropertyListRef)state);
    if(!s) {
        slot->markPreset([[self fileKey:url] UTF8String],url.lastPathComponent.stringByDeletingPathExtension.UTF8String);
        NSValue* cacheKey=[NSValue valueWithPointer:slot];NSArray* cached=presetLists[cacheKey];
        if(cached && ![cached filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == %@",[self fileKey:url]]].count) {
            presetLists[cacheKey]=[cached arrayByAddingObject:@{@"key":[self fileKey:url],@"name":url.lastPathComponent.stringByDeletingPathExtension,@"url":url}];
        }
    }
    if(self.afterEdit)self.afterEdit();
    info.stringValue=s?[NSString stringWithFormat:@"Preset読込失敗: %d",(int)s]:[NSString stringWithFormat:@"Preset: %@",url.lastPathComponent];[self refreshStatus];
}
- (void)installedPreset:(NSMenuItem*)sender { [self applyPresetURL:sender.representedObject index:sender.tag]; }
- (NSString*)fileKey:(NSURL*)url {return [@"file:" stringByAppendingString:url.URLByStandardizingPath.path];}
- (NSArray<NSDictionary*>*)presetOptions:(NSInteger)index {
    auto* slot=rack->slots[index].get();NSValue* key=[NSValue valueWithPointer:slot];
    NSArray* cached=presetLists[key];if(cached)return cached;
    NSMutableArray* options=[NSMutableArray new];
    for(auto& p:slot->factoryPresets())[options addObject:@{@"key":[NSString stringWithFormat:@"factory:%d",p.number],@"name":[NSString stringWithUTF8String:p.name.c_str()],@"number":@(p.number)}];
    for(NSURL* url in [self installedPresets:slot])[options addObject:@{@"key":[self fileKey:url],@"name":url.lastPathComponent.stringByDeletingPathExtension,@"url":url}];
    if(slot->presetKey.starts_with("file:") && ![options filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == %@",[NSString stringWithUTF8String:slot->presetKey.c_str()]]].count) {
        NSURL* url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:slot->presetKey.c_str()+5]];
        [options addObject:@{@"key":[self fileKey:url],@"name":url.lastPathComponent.stringByDeletingPathExtension,@"url":url}];
    }
    presetLists[key]=options;return options;
}
- (NSMenu*)presetMenuForIndex:(NSInteger)index {
    [self refreshStatus];auto& slot=*rack->slots[index];
    NSMenu* menu=[NSMenu new];NSMenu* installed=[NSMenu new];
    for(NSDictionary* option in [self presetOptions:index]) {
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:option[@"name"] action:@selector(choosePreset:) keyEquivalent:@""];
        item.target=self;item.tag=index;item.representedObject=option;
        item.state=slot.presetKey==[option[@"key"] UTF8String]?NSControlStateValueOn:NSControlStateValueOff;
        if(item.state==NSControlStateValueOn && slot.presetModified) {
            NSMutableDictionary* attrs=[DARTextAttributes(12,NSColor.labelColor) mutableCopy];NSFont* f=attrs[NSFontAttributeName];NSFont* italic=f?[NSFontManager.sharedFontManager convertFont:f toHaveTrait:NSItalicFontMask]:nil;if(italic)attrs[NSFontAttributeName]=italic;
            item.attributedTitle=[[NSAttributedString alloc] initWithString:[item.title stringByAppendingString:@" *"] attributes:attrs];
        }
        if(option[@"url"]) {item.toolTip=[option[@"url"] path];[installed addItem:item];}else [menu addItem:item];
    }
    if(installed.numberOfItems) {NSMenuItem* parent=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Installed Presets (%ld)",(long)installed.numberOfItems] action:nil keyEquivalent:@""];parent.submenu=installed;[menu addItem:parent];}
    if(!menu.numberOfItems){NSMenuItem* none=[[NSMenuItem alloc] initWithTitle:@"公開プリセットなし" action:nil keyEquivalent:@""];none.enabled=NO;[menu addItem:none];}
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem* file=[[NSMenuItem alloc] initWithTitle:@"Load .aupreset…" action:@selector(loadAUPreset:) keyEquivalent:@""];file.target=self;file.tag=index;[menu addItem:file];return menu;
}
- (void)presets:(NSButton*)sender {
    if(!editable || sender.tag<0 || sender.tag>=NSInteger(rack->slots.size()))return;
    NSMenu* menu=[self presetMenuForIndex:sender.tag];[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,sender.bounds.size.height) inView:sender];
}
- (void)choosePreset:(NSMenuItem*)sender {
    NSDictionary* option=sender.representedObject;
    if(option[@"url"]) [self applyPresetURL:option[@"url"] index:sender.tag];
    else {NSMenuItem* factory=[NSMenuItem new];factory.title=option[@"name"];factory.representedObject=@{@"slot":@(sender.tag),@"number":option[@"number"]};[self selectPreset:factory];}
}
- (void)stepPreset:(NSInteger)index direction:(NSInteger)direction {
    if(!editable || index<0 || index>=NSInteger(rack->slots.size()))return;
    NSArray* options=[self presetOptions:index];if(!options.count)return;
    NSInteger current=-1;for(NSUInteger i=0;i<options.count;++i)if(rack->slots[index]->presetKey==[options[i][@"key"] UTF8String]){current=i;break;}
    NSInteger next=current<0?(direction>0?0:options.count-1):(current+direction+NSInteger(options.count))%NSInteger(options.count);
    NSMenuItem* item=[NSMenuItem new];item.tag=index;item.representedObject=options[next];[self choosePreset:item];
}
- (void)previousPreset:(NSButton*)sender {[self stepPreset:sender.tag direction:-1];}
- (void)nextPreset:(NSButton*)sender {[self stepPreset:sender.tag direction:1];}
- (void)selectPreset:(NSMenuItem*)sender {
    NSInteger index=[sender.representedObject[@"slot"] integerValue];
    if(!editable || index<0 || index>=NSInteger(rack->slots.size()))return;
    if(self.beforeEdit)self.beforeEdit();
    selectedSlot=rack->slots[index].get();
    OSStatus s=rack->slots[index]->applyFactoryPreset([sender.representedObject[@"number"] intValue]);
    if(!s)rack->slots[index]->markPreset([[NSString stringWithFormat:@"factory:%d",[sender.representedObject[@"number"] intValue]] UTF8String],sender.title.UTF8String);
    if(self.afterEdit)self.afterEdit();
    info.stringValue=s?[NSString stringWithFormat:@"Preset読込失敗: %d",(int)s]:[NSString stringWithFormat:@"Preset: %@",sender.title];
    [self refreshStatus];
}
- (void)loadAUPreset:(NSMenuItem*)sender {
    if(!editable || sender.tag<0 || sender.tag>=NSInteger(rack->slots.size()))return;
    AUEffect* expected=rack->slots[sender.tag].get();NSInteger index=sender.tag;
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.allowsMultipleSelection=NO;panel.canChooseDirectories=NO;
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK || !editable || index>=NSInteger(rack->slots.size()) || rack->slots[index].get()!=expected)return;
        [self applyPresetURL:panel.URL index:index];
    }];
}
- (NSDictionary*)presetMetadata:(AUEffect*)slot {
    NSMutableArray* baseline=[NSMutableArray new];
    for(auto& p:slot->presetBaseline)if(std::isfinite(p.value))[baseline addObject:@[@(p.id),@(p.scope),@(p.element),@(p.value)]];
    return @{@"key":[NSString stringWithUTF8String:slot->presetKey.c_str()],@"name":[NSString stringWithUTF8String:slot->presetName.c_str()],@"baseline":baseline};
}
- (void)restorePresetMetadata:(id)data slot:(AUEffect*)slot {
    if(![data isKindOfClass:NSDictionary.class] || ![data[@"key"] isKindOfClass:NSString.class] || [data[@"key"] length]>4096 || ![data[@"name"] isKindOfClass:NSString.class] || [data[@"name"] length]>1024 || ![data[@"baseline"] isKindOfClass:NSArray.class] || [data[@"baseline"] count]>16384)return;
    std::vector<AUEffect::PresetParameter> baseline;
    for(id p in data[@"baseline"]) {
        if(![p isKindOfClass:NSArray.class] || [p count]!=4)return;
        for(id value in p)if(![value isKindOfClass:NSNumber.class])return;
        UInt32 scope=[p[1] unsignedIntValue],element=[p[2] unsignedIntValue];float value=[p[3] floatValue];
        if(scope>kAudioUnitScope_Output || element>=64 || !std::isfinite(value))return;
        baseline.push_back({[p[0] unsignedIntValue],scope,element,value});
    }
    slot->presetKey=[data[@"key"] UTF8String];slot->presetName=[data[@"name"] UTF8String];slot->presetBaseline=std::move(baseline);slot->refreshPresetModified();
}
- (void)save:(id)sender {
    if(!editable) return;
    NSSavePanel* panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"Dutchman AU Rack.plist";
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result) {
        if(result!=NSModalResponseOK || !editable) return;
        NSMutableArray* entries=[NSMutableArray new];
        if(self.beforeEdit) self.beforeEdit();
        for(auto& slot:rack->slots) {
            CFPropertyListRef state=slot->copyState();
            if(!state) { if(self.afterEdit) self.afterEdit(); info.stringValue=@"状態を取得できないスロットがあります。保存を中止しました。"; return; }
            auto d=slot->choice.description;
            [entries addObject:@{@"type":@(d.componentType),@"subtype":@(d.componentSubType),@"manufacturer":@(d.componentManufacturer),@"name":[NSString stringWithUTF8String:slot->choice.name.c_str()],@"bypass":@(slot->bypass.load()),@"state":CFBridgingRelease(state),@"presetSource":[self presetMetadata:slot.get()]}];
        }
        if(self.afterEdit) self.afterEdit();
        NSError* error=nil; NSData* data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"slots":entries} format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if(data && [data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) info.stringValue=@"AU Rackを保存しました。";
        else info.stringValue=error.localizedDescription?:@"保存失敗";
    }];
}
- (void)load:(id)sender {
    if(!editable) return;
    NSOpenPanel* panel=[NSOpenPanel openPanel]; panel.allowsMultipleSelection=NO; panel.canChooseDirectories=NO;
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result) {
        if(result!=NSModalResponseOK || !editable) return;
        NSError* error=nil; NSData* data=[NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
        id root=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&error]:nil;
        if(![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isEqual:@1] || ![root[@"slots"] isKindOfClass:NSArray.class] || [root[@"slots"] count]>AURack::maximumSlots) { info.stringValue=@"有効なAU Rackファイルではありません。"; return; }
        std::vector<std::unique_ptr<AUEffect>> next;
        for(id entry in root[@"slots"]) {
            if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"type"] isKindOfClass:NSNumber.class] || [entry[@"type"] unsignedIntValue]!=kAudioUnitType_Effect || ![entry[@"subtype"] isKindOfClass:NSNumber.class] || ![entry[@"manufacturer"] isKindOfClass:NSNumber.class] || ![entry[@"name"] isKindOfClass:NSString.class] || ![entry[@"bypass"] isKindOfClass:NSNumber.class] || ![entry[@"state"] isKindOfClass:NSDictionary.class]) { info.stringValue=@"スロット情報が不正です。元のRackを維持します。"; return; }
            AUChoice choice{{[entry[@"type"] unsignedIntValue],[entry[@"subtype"] unsignedIntValue],[entry[@"manufacturer"] unsignedIntValue],0,0},[entry[@"name"] UTF8String]};
            auto slot=std::make_unique<AUEffect>(choice); OSStatus s=slot->prepare(self.processingRate);
            if(!s) s=slot->restore((__bridge CFPropertyListRef)entry[@"state"]);
            if(s) { info.stringValue=[NSString stringWithFormat:@"復元失敗 (%d)。元のRackを維持します。",(int)s]; return; }
            slot->bypass=[entry[@"bypass"] boolValue]; [self restorePresetMetadata:entry[@"presetSource"] slot:slot.get()]; next.push_back(std::move(slot));
        }
        if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; [presetLists removeAllObjects]; rack->slots=std::move(next); if(self.afterEdit) self.afterEdit(); [self rebuild]; info.stringValue=@"AU Rackを復元しました。ミュート状態を維持して再開します。";
    }];
}
@end
