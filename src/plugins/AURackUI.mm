#ifdef DAR_ENABLE_VST3
#include "VST3Host.hpp"
#endif
#import "AURackUI.h"
#import "RackSlotView.h"
#include "../RackSettings.hpp"
#include <algorithm>
#import <CoreAudioKit/CoreAudioKit.h>
#import "../DrawText.h"
#import "../Theme.h"
#import <AudioToolbox/AUCocoaUIView.h>
@implementation AURackUI {
    AURack* rack;
    NSString* dragIdentity;
    NSUInteger rackRevision;
    DSPParameters* dspParameters;
    SpatialParameters* spatialParameters;
    std::vector<AUChoice> choices;
#ifdef DAR_ENABLE_VST3
    std::vector<VST3Choice> vstChoices;
    BOOL vstScanRunning;
#endif
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
    RackEffect* selectedSlot;
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
    if((self=[super init])) { cards=[NSMutableArray new];miniMeters=[NSMutableArray new];presetButtons=[NSMutableArray new];presetLists=[NSMutableDictionary new];sizeObservers=[NSMutableDictionary new]; dragIdentity=NSUUID.UUID.UUIDString; rack=value; self.processingRate=48000; editable=YES; editors=[NSMutableDictionary new]; factories=[NSMutableDictionary new]; editButtons=[NSMutableArray new]; labels=[NSMutableArray new]; }
    return self;
}
- (void)show {
    if(!window) {
        window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,820,520) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO; window.title=@"The Dutchman BOX/DAR — Rack";
        window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSStackView* root=[NSStackView stackViewWithViews:@[]]; root.orientation=NSUserInterfaceLayoutOrientationVertical; root.alignment=NSLayoutAttributeLeading; root.spacing=6; root.translatesAutoresizingMaskIntoConstraints=NO;
        [window.contentView addSubview:root];
        [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:8],[root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-8],[root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:8]]];

        [root addArrangedSubview:[NSStackView stackViewWithViews:@[[self button:@"Scan AU" action:@selector(scan:) tag:0 editing:YES],
#ifdef DAR_ENABLE_VST3
[self button:@"Scan VST3" action:@selector(scanVST3:) tag:0 editing:YES],
#endif
[self button:@"Save the Rack…" action:@selector(save:) tag:0 editing:YES],[self button:@"Load the Rack…" action:@selector(load:) tag:0 editing:YES]]]];
        rows=[NSStackView stackViewWithViews:@[]]; rows.orientation=NSUserInterfaceLayoutOrientationVertical; rows.alignment=NSLayoutAttributeLeading; rows.spacing=6;
        slotScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,760,100)];slotScroll.hasVerticalScroller=YES;slotScroll.drawsBackground=YES;slotScroll.backgroundColor=DARDeep();slotScroll.autohidesScrollers=YES;slotScroll.documentView=rows;rows.autoresizingMask=NSViewWidthSizable;
        [root addArrangedSubview:slotScroll];[slotScroll.bottomAnchor constraintEqualToAnchor:root.superview.bottomAnchor constant:-32].active=YES;[slotScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
        info=[NSTextField wrappingLabelWithString:@"再生中もRackを変更できます。変更時は処理出力を短く休止します。"];
        [root addArrangedSubview:info]; [info.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
        if(editable) [self scan:nil];
#ifdef DAR_ENABLE_VST3
        vstChoices=cachedVST3Effects();
        if([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"local.ryuji.DesktopAudioRack"])[self startVST3Scan:NO];
#endif
        [self rebuild]; [window center];
    }
    [window makeKeyAndOrderFront:nil];
}
- (NSView*)embeddedView {
    if(!embedded) { [self show]; [window orderOut:nil]; embedded=window.contentView; window.contentView=[NSView new]; embedded.translatesAutoresizingMaskIntoConstraints=NO; embeddedHeight=[embedded.heightAnchor constraintEqualToConstant:230]; embeddedHeight.active=NO; }
    return embedded;
}
- (void)setEditingAllowed:(BOOL)allowed {
    editable=allowed;
    for(DARRackSlotView* card in rows.arrangedSubviews)card.canDrag=allowed && card.slotNumber<=NSInteger(rack->slots.size()) && rack->slots[card.slotNumber-1]!=nullptr;
    for(NSButton* b in editButtons) {
        BOOL presetControl=b.action==@selector(presets:) || b.action==@selector(previousPreset:) || b.action==@selector(nextPreset:);
        BOOL vstPreset=presetControl && b.tag>=0 && size_t(b.tag)<rack->slots.size() && rack->slots[b.tag] && rack->slots[b.tag]->isVST3();
        BOOL enabled=allowed && !vstPreset;
#ifdef DAR_ENABLE_VST3
        if(b.action==@selector(scanVST3:)&&vstScanRunning)enabled=NO;
#endif
        if(b.enabled!=enabled)b.enabled=enabled;
    }
}
- (void)scan:(id)sender {
    if(!editable) return;
    choices=scanAUEffects();
    info.stringValue=[NSString stringWithFormat:@"%zu AUv2 Effect候補。Stereo対応は追加時に検証します。",choices.size()];
}
- (NSInteger)firstEmptySlot {for(size_t i=0;i<AURack::maximumSlots;++i)if(i>=rack->slots.size()||!rack->slots[i])return i;return -1;}
- (NSMenu*)effectMenuForSlot:(NSInteger)destination {
    BOOL replacing=destination>=0 && size_t(destination)<rack->slots.size();
    NSMenu* menu=[NSMenu new];
    if(!editable || (!replacing && [self firstEmptySlot]<0)) {
        NSString* title=[self firstEmptySlot]<0?@"Rack is full (8/8)":@"AUがありません。Scan AUを実行してください。";
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];item.enabled=NO;[menu addItem:item];return menu;
    }
    NSMutableDictionary<NSString*,NSMenu*>* manufacturers=[NSMutableDictionary new];
    for(size_t i=0;i<choices.size();++i) {
        NSString* name=[NSString stringWithUTF8String:choices[i].name.c_str()];NSRange separator=[name rangeOfString:@":"];
        NSString* maker=separator.location==NSNotFound?@"Audio Units":[name substringToIndex:separator.location];
        NSMenu* group=manufacturers[maker];
        if(!group){group=[NSMenu new];manufacturers[maker]=group;NSMenuItem* parent=[[NSMenuItem alloc] initWithTitle:maker action:nil keyEquivalent:@""];parent.submenu=group;[menu addItem:parent];}
        NSString* title=separator.location==NSNotFound?name:[[name substringFromIndex:separator.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:@selector(addChosenEffect:) keyEquivalent:@""];item.target=self;item.tag=i;item.representedObject=@(destination);[group addItem:item];
    }
#ifdef DAR_ENABLE_VST3
    if(!vstChoices.empty()){
        NSMenu* vst=[NSMenu new];NSMenuItem* parent=[[NSMenuItem alloc] initWithTitle:@"VST3" action:nil keyEquivalent:@""];parent.submenu=vst;[menu addItem:parent];
        for(size_t i=0;i<vstChoices.size();++i){NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:vstChoices[i].name.c_str()] action:@selector(addVST3:) keyEquivalent:@""];item.target=self;item.tag=i;item.representedObject=@{@"destination":@(destination),@"path":[NSString stringWithUTF8String:vstChoices[i].path.c_str()],@"cid":[NSString stringWithUTF8String:vstChoices[i].cid.c_str()],@"name":[NSString stringWithUTF8String:vstChoices[i].name.c_str()]};[vst addItem:item];}
    }
#endif
    return menu;
}
- (NSMenu*)effectMenu {return [self effectMenuForSlot:-1];}
- (void)chooseEffectForSlot:(NSInteger)index view:(NSView*)view {
    if(!editable||index<0||size_t(index)>=rack->slots.size())return;
    [[self effectMenuForSlot:index] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,view.bounds.size.height) inView:view];
}
- (BOOL)installEffect:(std::unique_ptr<RackEffect>)slot atIndex:(NSInteger)index {
    if(index==-1)index=[self firstEmptySlot];
    if(!editable||index<0||index>=NSInteger(AURack::maximumSlots))return NO;
    BOOL replacing=size_t(index)<rack->slots.size() && rack->slots[index]!=nullptr;
    OSStatus status=slot->prepare(self.processingRate);
    if(status){info.stringValue=[NSString stringWithFormat:@"%@ 初期化失敗 (%d / %s)。Rackは維持します。",[NSString stringWithUTF8String:slot->choice.name.c_str()],int(status),slot->errorDetail()];return NO;}
    if(replacing)slot->bypass=rack->slots[index]->bypass.load();
    if(self.beforeEdit)self.beforeEdit();
    selectedSlot=slot.get();
    if(replacing){[self closeEditors];[presetLists removeObjectForKey:[NSValue valueWithPointer:rack->slots[index].get()]];rack->slots[index]=std::move(slot);}
    else {if(size_t(index)>=rack->slots.size())rack->slots.resize(index+1);rack->slots[index]=std::move(slot);}
    if(self.afterEdit)self.afterEdit();[self rebuild];return YES;
}
- (BOOL)acceptDragPayload:(NSDictionary*)payload {
    return editable && [payload[@"rack"] isEqual:dragIdentity] && [payload[@"revision"] isKindOfClass:NSNumber.class] && [payload[@"revision"] unsignedIntegerValue]==rackRevision && [payload[@"source"] isKindOfClass:NSNumber.class] && [payload[@"source"] integerValue]>=0 && [payload[@"source"] unsignedIntegerValue]<rack->slots.size() && rack->slots[[payload[@"source"] unsignedIntegerValue]]!=nullptr;
}
- (BOOL)moveSlotFrom:(NSInteger)source toSlot:(NSInteger)destination {
    if(!editable||source<0||size_t(source)>=rack->slots.size()||!rack->slots[source]||destination<0||destination>=NSInteger(AURack::maximumSlots))return NO;
    if(destination==source)return YES;
    if(self.beforeEdit)self.beforeEdit();[self closeEditors];
    if(size_t(destination)>=rack->slots.size())rack->slots.resize(destination+1);
    std::swap(rack->slots[source],rack->slots[destination]);
    if(self.afterEdit)self.afterEdit();[self rebuild];return YES;
}
#ifdef DAR_ENABLE_VST3
- (void)scanVST3:(id)sender {if(editable)[self startVST3Scan:YES];}
- (void)startVST3Scan:(BOOL)force {
    if(vstScanRunning)return;vstScanRunning=YES;[self setEditingAllowed:editable];
    NSString* progress=force?@"VST3を全件再スキャンしています…":@"VST3キャッシュを使用中・変更分を確認しています…";info.stringValue=progress;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{std::string report;auto found=scanVST3Effects(report,force);dispatch_async(dispatch_get_main_queue(),^{vstChoices=found;vstScanRunning=NO;NSString* status=[NSString stringWithUTF8String:report.c_str()];if([info.stringValue isEqualToString:progress])info.stringValue=status;else info.toolTip=status;[self setEditingAllowed:editable];});}});
}
- (void)addVST3:(NSMenuItem*)sender {
    // Capture the choice in the menu item: a background refresh may reorder the catalog.
    id selection=sender.representedObject;
    if(![selection isKindOfClass:NSDictionary.class]||![selection[@"destination"] isKindOfClass:NSNumber.class]||![selection[@"path"] isKindOfClass:NSString.class]||![selection[@"cid"] isKindOfClass:NSString.class]||![selection[@"name"] isKindOfClass:NSString.class])return;
    VST3Choice choice{[selection[@"path"] UTF8String],[selection[@"cid"] UTF8String],[selection[@"name"] UTF8String]};
    [self installEffect:std::make_unique<VST3Effect>(choice) atIndex:[selection[@"destination"] integerValue]];
}
- (void)addVST3Choice:(const VST3Choice&)choice { [self installEffect:std::make_unique<VST3Effect>(choice) atIndex:-1]; }

#endif
- (void)add:(NSButton*)sender {
    if(!editable)return;
    [[self effectMenuForSlot:sender.tag] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,sender.bounds.size.height) inView:sender];
}
- (void)addChosenEffect:(NSMenuItem*)sender {
    if(sender.tag<0||sender.tag>=NSInteger(choices.size()))return;
    NSInteger destination=[sender.representedObject isKindOfClass:NSNumber.class]?[sender.representedObject integerValue]:-1;
    [self installEffect:std::make_unique<AUEffect>(choices[sender.tag]) atIndex:destination];
}
- (void)rebuild {
    ++rackRevision;
    __weak AURackUI* weakSelf=self;
    NSUInteger toolbarCount=3;
#ifdef DAR_ENABLE_VST3
    toolbarCount=4;
#endif
    while(editButtons.count>toolbarCount) [editButtons removeLastObject];
    for(NSView* row in [rows.arrangedSubviews copy]) { [rows removeArrangedSubview:row]; [row removeFromSuperview]; }
    [labels removeAllObjects];[presetButtons removeAllObjects];[cards removeAllObjects];[miniMeters removeAllObjects];
    for(size_t i=0;i<AURack::maximumSlots;++i) {
        DARRackSlotView* card=[DARRackSlotView new];card.slotNumber=i+1;
        card.canDrag=editable && i<rack->slots.size() && rack->slots[i]!=nullptr;card.toolTip=@"番号またはプラグイン名をドラッグして並べ替え";
        card.dragPayload=@{@"rack":dragIdentity,@"revision":@(rackRevision),@"source":@(i)};
        card.acceptPayload=^BOOL(NSDictionary* payload){return [weakSelf acceptDragPayload:payload];};
        card.movePayload=^BOOL(NSDictionary* payload,NSInteger boundary){return [weakSelf acceptDragPayload:payload] && [weakSelf moveSlotFrom:[payload[@"source"] integerValue] toSlot:boundary];};card.translatesAutoresizingMaskIntoConstraints=NO;[rows addArrangedSubview:card];
        [card.heightAnchor constraintEqualToConstant:62].active=YES;
        [card.widthAnchor constraintEqualToAnchor:slotScroll.contentView.widthAnchor constant:-12].active=YES;
        if(i>=rack->slots.size() || !rack->slots[i]) {
            [cards addObject:card];[labels addObject:[NSTextField labelWithString:@""]];[presetButtons addObject:[NSButton new]];[miniMeters addObject:[DARMiniMeter new]];
            NSButton* add=[self button:@"+ Add an effect" action:@selector(add:) tag:i editing:YES];add.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:add];
            [NSLayoutConstraint activateConstraints:@[[add.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:70],[add.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],[add.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],[add.heightAnchor constraintEqualToConstant:30]]];continue;
        }
        [cards addObject:card];
        DARRackSlotName* name=[DARRackSlotName labelWithString:@""];name.rackCard=card;name.toolTip=@"クリックでプラグインを変更 / ドラッグで並べ替え";
        __weak DARRackSlotName* weakName=name;name.activate=^{[weakSelf chooseEffectForSlot:i view:weakName];};name.accessibilityRole=NSAccessibilityButtonRole;name.font=[NSFont boldSystemFontOfSize:14];name.lineBreakMode=NSLineBreakByTruncatingTail;[labels addObject:name];
        NSButton* bypass=[NSButton checkboxWithTitle:@"Bypass" target:self action:@selector(bypass:)];bypass.tag=i;bypass.state=rack->slots[i]->bypass?NSControlStateValueOn:NSControlStateValueOff;
        DARMiniMeter* meter=[DARMiniMeter new];[meter.widthAnchor constraintEqualToConstant:70].active=YES;[meter.heightAnchor constraintEqualToConstant:26].active=YES;[miniMeters addObject:meter];
        NSStackView* controls=[NSStackView stackViewWithViews:@[name,meter,bypass,[self button:@"Editor ↗" action:@selector(editor:) tag:i editing:NO],[self button:@"↑" action:@selector(up:) tag:i editing:YES],[self button:@"↓" action:@selector(down:) tag:i editing:YES],[self button:@"×" action:@selector(remove:) tag:i editing:YES]]];controls.spacing=6;controls.distribution=NSStackViewDistributionFill;[name setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];[name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSButton* preset=[self button:@"Preset: 未選択" action:@selector(presets:) tag:i editing:YES];preset.alignment=NSTextAlignmentLeft;[presetButtons addObject:preset];
        NSStackView* browser=[NSStackView stackViewWithViews:@[[self button:@"−" action:@selector(previousPreset:) tag:i editing:YES],preset,[self button:@"+" action:@selector(nextPreset:) tag:i editing:YES]]];browser.spacing=6;browser.distribution=NSStackViewDistributionFill;[preset setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        for(NSView* bar in @[controls,browser]){bar.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:bar];[bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:70].active=YES;[bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active=YES;}
        [controls.topAnchor constraintEqualToAnchor:card.topAnchor constant:4].active=YES;[controls.heightAnchor constraintEqualToConstant:24].active=YES;[browser.topAnchor constraintEqualToAnchor:card.topAnchor constant:32].active=YES;[browser.heightAnchor constraintEqualToConstant:24].active=YES;
    }
    [rows setFrameSize:NSMakeSize(MAX(700,slotScroll.contentSize.width),MAX(1,rows.fittingSize.height))];
    [self setEditingAllowed:editable];
    [self refreshStatus];
}
- (void)closeEditors { for(auto& slot:rack->slots)if(slot)slot->closeEditor(); for(id token in sizeObservers.allValues) [NSNotificationCenter.defaultCenter removeObserver:token]; [sizeObservers removeAllObjects]; for(NSWindow* w in editors.allValues) { [w close]; w.contentView=nil; } [editors removeAllObjects]; [factories removeAllObjects]; }
- (void)remove:(NSButton*)sender { if(!editable) return; [presetLists removeObjectForKey:[NSValue valueWithPointer:rack->slots[sender.tag].get()]]; if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; rack->slots[sender.tag].reset(); if(self.afterEdit) self.afterEdit(); [self rebuild]; }
- (void)up:(NSButton*)sender {[self moveSlotFrom:sender.tag toSlot:sender.tag-1];}
- (void)down:(NSButton*)sender {[self moveSlotFrom:sender.tag toSlot:sender.tag+1];}
- (void)bypass:(NSButton*)sender { rack->slots[sender.tag]->bypass=sender.state==NSControlStateValueOn; }
- (void)refreshStatus {
    if(!window) return;
    double total=0; BOOL unknown=NO;
    for(size_t i=0;i<rack->slots.size();++i) {
        if(!rack->slots[i])continue;
        auto& slot=*rack->slots[i];slot.idle(); double latency=slot.latency();
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
        if(slot.isVST3())title=@"VST3 · プリセットはEditor内で選択";
        NSAttributedString* displayTitle=[[NSAttributedString alloc] initWithString:title attributes:attributes];
        if(![presetButtons[i].attributedTitle isEqualToAttributedString:displayTitle])presetButtons[i].attributedTitle=displayTitle;
        if(![presetButtons[i].toolTip isEqualToString:title])presetButtons[i].toolTip=title;
        NSWindow* editor=editors[@(i)];if(editor)editor.title=[NSString stringWithFormat:@"%@ — %@",[NSString stringWithUTF8String:slot.choice.name.c_str()],title];
    }
    NSString* latencyTitle=[NSString stringWithFormat:@"Rack — Reported latency %.2f ms%@",total*1000,unknown?@" + unknown":@""];
    window.title=latencyTitle; info.toolTip=latencyTitle;
}
- (void)editor:(NSButton*)sender {
    selectedSlot=rack->slots[sender.tag].get();[self refreshStatus];
    auto& slot=*rack->slots[sender.tag]; if(slot.isVST3()){if(!slot.showEditor())info.stringValue=@"VST3のNSView Editorを開けませんでした。";return;} AudioUnit unit=slot.handle(); if(!unit || slot.error) return;
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
- (BOOL)state:(id)state matches:(RackEffect*)slot {
    auto d=slot->choice.description;
    return [state isKindOfClass:NSDictionary.class] && [state[@"type"] isKindOfClass:NSNumber.class] && [state[@"type"] unsignedIntValue]==d.componentType && [state[@"subtype"] isKindOfClass:NSNumber.class] && [state[@"subtype"] unsignedIntValue]==d.componentSubType && [state[@"manufacturer"] isKindOfClass:NSNumber.class] && [state[@"manufacturer"] unsignedIntValue]==d.componentManufacturer;
}
- (NSArray<NSURL*>*)installedPresets:(RackEffect*)slot {
    if(slot->isVST3())return @[];
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
    RackEffect* expected=rack->slots[sender.tag].get();NSInteger index=sender.tag;
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.allowsMultipleSelection=NO;panel.canChooseDirectories=NO;
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK || !editable || index>=NSInteger(rack->slots.size()) || rack->slots[index].get()!=expected)return;
        [self applyPresetURL:panel.URL index:index];
    }];
}
- (NSDictionary*)presetMetadata:(RackEffect*)slot {
    NSMutableArray* baseline=[NSMutableArray new];
    for(auto& p:slot->presetBaseline)if(std::isfinite(p.value))[baseline addObject:@[@(p.id),@(p.scope),@(p.element),@(p.value)]];
    return @{@"key":[NSString stringWithUTF8String:slot->presetKey.c_str()],@"name":[NSString stringWithUTF8String:slot->presetName.c_str()],@"baseline":baseline};
}
- (void)restorePresetMetadata:(id)data slot:(RackEffect*)slot {
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
- (void)setDSPParameters:(DSPParameters*)dsp spatialParameters:(SpatialParameters*)spatial { dspParameters=dsp;spatialParameters=spatial; }
- (NSDictionary*)rackDocument {
    if(!editable)return nil;
    NSMutableArray* entries=[NSMutableArray new];
    if(self.beforeEdit) self.beforeEdit();
    for(auto& slot:rack->slots) {
        if(!slot){[entries addObject:@{@"empty":@YES}];continue;}
        CFPropertyListRef state=slot->copyState();
        if(!state) { if(self.afterEdit) self.afterEdit(); info.stringValue=@"状態を取得できないスロットがあります。保存を中止しました。"; return nil; }
        auto d=slot->choice.description;if(slot->isVST3())d.componentType=kAudioUnitType_Effect;
        [entries addObject:@{@"type":@(d.componentType),@"subtype":@(d.componentSubType),@"manufacturer":@(d.componentManufacturer),@"name":[NSString stringWithUTF8String:slot->choice.name.c_str()],@"bypass":@(slot->bypass.load()),@"state":CFBridgingRelease(state),@"presetSource":[self presetMetadata:slot.get()]}];
    }
    NSDictionary* settings=(dspParameters&&spatialParameters)?RackSettings::capture(*dspParameters,*spatialParameters).encode():nil;
    if(self.afterEdit) self.afterEdit();
    NSInteger version=4;
    NSMutableDictionary* document=[@{@"version":@(version),@"slots":entries} mutableCopy];if(settings)document[@"settings"]=settings;return document;
}
- (void)save:(id)sender {
    if(!editable)return;
    NSSavePanel* panel=[NSSavePanel savePanel];panel.nameFieldStringValue=@"Dutchman Rack.plist";
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK||!editable)return;
        NSDictionary* document=[self rackDocument];if(!document)return;
        NSError* error=nil;NSData* data=[NSPropertyListSerialization dataWithPropertyList:document format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if(data&&[data writeToURL:panel.URL options:NSDataWritingAtomic error:&error])info.stringValue=@"Rackを保存しました。";
        else info.stringValue=error.localizedDescription?:@"保存失敗";
    }];
}
- (BOOL)restoreRackDocument:(id)root {
    if(!editable)return NO;
    if(![root isKindOfClass:NSDictionary.class] || (![root[@"version"] isEqual:@1] && ![root[@"version"] isEqual:@2] && ![root[@"version"] isEqual:@3] && ![root[@"version"] isEqual:@4]) || ![root[@"slots"] isKindOfClass:NSArray.class] || [root[@"slots"] count]>AURack::maximumSlots) { info.stringValue=@"有効なRackファイルではありません。"; return NO; }
    RackSettings settings;BOOL hasSettings=[root[@"version"] isEqual:@3] || ([root[@"version"] isEqual:@4] && root[@"settings"]!=nil);
    if(hasSettings&&(!dspParameters||!spatialParameters||!RackSettings::decode(root[@"settings"],settings))){info.stringValue=@"Gain / GEQ / Spatial設定が不正です。元のRackを維持します。";return NO;}
    std::vector<std::unique_ptr<RackEffect>> next;
    for(id entry in root[@"slots"]) {
        if([root[@"version"] isEqual:@4] && [entry isKindOfClass:NSDictionary.class] && [entry[@"empty"] isEqual:@YES]){next.push_back(nullptr);continue;}
        if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"type"] isKindOfClass:NSNumber.class] || [entry[@"type"] unsignedIntValue]!=kAudioUnitType_Effect || ![entry[@"subtype"] isKindOfClass:NSNumber.class] || ![entry[@"manufacturer"] isKindOfClass:NSNumber.class] || ![entry[@"name"] isKindOfClass:NSString.class] || ![entry[@"bypass"] isKindOfClass:NSNumber.class] || ![entry[@"state"] isKindOfClass:NSDictionary.class]) { info.stringValue=@"スロット情報が不正です。元のRackを維持します。"; return NO; }
        AUChoice choice{{[entry[@"type"] unsignedIntValue],[entry[@"subtype"] unsignedIntValue],[entry[@"manufacturer"] unsignedIntValue],0,0},[entry[@"name"] UTF8String]};
        std::unique_ptr<RackEffect> slot;
#ifdef DAR_ENABLE_VST3
        id state=entry[@"state"];
        if([state[@"format"] isEqual:@"VST3"]){
            if(![state[@"path"] isKindOfClass:NSString.class]||![state[@"cid"] isKindOfClass:NSString.class]){info.stringValue=@"VST3識別情報が不正です。";return NO;}
            slot=std::make_unique<VST3Effect>(VST3Choice{[state[@"path"] UTF8String],[state[@"cid"] UTF8String],[entry[@"name"] UTF8String]});
        }else
#endif
        slot=std::make_unique<AUEffect>(choice);
        OSStatus s=slot->prepare(self.processingRate);
        if(!s) s=slot->restore((__bridge CFPropertyListRef)entry[@"state"]);
        if(s) { info.stringValue=[NSString stringWithFormat:@"復元失敗 (%d)。元のRackを維持します。",(int)s]; return NO; }
        slot->bypass=[entry[@"bypass"] boolValue]; [self restorePresetMetadata:entry[@"presetSource"] slot:slot.get()]; next.push_back(std::move(slot));
    }
    if(self.beforeEdit) self.beforeEdit(); [self closeEditors]; [presetLists removeAllObjects]; rack->slots=std::move(next); if(hasSettings)settings.apply(*dspParameters,*spatialParameters); if(self.afterEdit) self.afterEdit(); [self rebuild]; if(hasSettings&&self.settingsDidLoad)self.settingsDidLoad(); info.stringValue=@"Rackを復元しました。ミュート状態を維持して再開します。";
    return YES;
}
- (void)load:(id)sender {
    if(!editable)return;
    NSOpenPanel* panel=[NSOpenPanel openPanel];panel.allowsMultipleSelection=NO;panel.canChooseDirectories=NO;
    [panel beginSheetModalForWindow:(embedded.window?:window) completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK||!editable)return;
        NSError* error=nil;NSData* data=[NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
        id root=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&error]:nil;
        [self restoreRackDocument:root];
    }];
}
@end
