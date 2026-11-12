#import "MeterView.h"
#import "Theme.h"
#import "DrawText.h"
#include <algorithm>
#include <cmath>
@implementation DARMeterView {
    NSString* caption;
    float level[2],hold[2];
    double holdUntil[2],lastTime;
    BOOL clip[2];
}
- (instancetype)initWithTitle:(NSString*)title {
    if((self=[super initWithFrame:NSZeroRect])) {
        caption=title; level[0]=level[1]=hold[0]=hold[1]=-60;
        self.toolTip=@"Stereo sample-peak meter · クリックでPeak Hold / Clipをリセット";
        [self setAccessibilityElement:YES]; [self setAccessibilityLabel:title];
    } return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(410,154); }
- (BOOL)isFlipped { return YES; }
- (void)clearHold { hold[0]=hold[1]=-60; holdUntil[0]=holdUntil[1]=0; clip[0]=clip[1]=NO; self.needsDisplay=YES; }
- (void)mouseDown:(NSEvent*)event { [self clearHold]; }
- (void)updateLeft:(float)left right:(float)right time:(double)now {
    float values[2]{left,right}; double dt=lastTime?std::clamp(now-lastTime,0.,1.):0; lastTime=now;
    for(int ch=0;ch<2;ch++) {
        float db=20*log10f(std::max(values[ch],1e-6f));
        level[ch]=std::max(db,level[ch]-float(24*dt));
        if(db>=hold[ch]) { hold[ch]=db; holdUntil[ch]=now+1.5; }
        else if(now>holdUntil[ch]) hold[ch]=std::max(level[ch],hold[ch]-float(12*dt));
        if(values[ch]>=1) clip[ch]=YES;
    }
    [self setAccessibilityValue:[NSString stringWithFormat:@"L %.1f, R %.1f dBFS",level[0],level[1]]];
    self.needsDisplay=YES;
}
- (void)text:(NSString*)text x:(CGFloat)x y:(CGFloat)y color:(NSColor*)color size:(CGFloat)size {
    DARDrawText(text,NSMakePoint(x,y),size,color);
}
- (void)drawRect:(NSRect)dirty {
    [DARDeep() setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    if(self.vertical) {
        CGFloat h=MAX(40,self.bounds.size.height-60),top=26;
        [self text:caption x:8 y:6 color:DARAmber() size:11];
        for(int ch=0;ch<2;++ch) {
            CGFloat x=16+ch*28;
            for(int seg=0;seg<40;++seg) {
                float db=-60+seg*1.5;
                NSColor* color=db>=-3?DARRed():(db>=-12?DARAmber():NSColor.systemGreenColor);
                [(db<level[ch]?color:DARColor(0x1C324C)) setFill];NSRectFill(NSMakeRect(x,top+h-(seg+1)*h/40,18,h/40-1));
            }
            if(hold[ch]>-60){[DARAmber() setFill];NSRectFill(NSMakeRect(x,top+h-std::clamp((hold[ch]+60)/60.f,0.f,1.f)*h,18,1.5));}
            [self text:ch?@"R":@"L" x:x+4 y:top+h+3 color:NSColor.lightGrayColor size:9];
            [self text:level[ch]<-60?@"−∞":[NSString stringWithFormat:@"%.1f",level[ch]] x:x-3 y:top+h+17 color:clip[ch]?DARRed():NSColor.whiteColor size:8];
        }
        for(int db=-60;db<=0;db+=12)[self text:[NSString stringWithFormat:@"%d",db] x:74 y:top+h-(db+60)/60.*h-4 color:NSColor.grayColor size:8];
        return;
    }
    [self text:caption x:16 y:12 color:NSColor.whiteColor size:13];
    [self text:@"SAMPLE PEAK / dBFS" x:160 y:14 color:NSColor.grayColor size:10];
    CGFloat x=38,width=self.bounds.size.width-116;
    for(int db=-60;db<=0;db+=12) [self text:[NSString stringWithFormat:@"%d",db] x:x+(db+60)/60.*width-8 y:36 color:NSColor.grayColor size:9];
    for(int ch=0;ch<2;++ch) {
        CGFloat y=57+ch*38;
        [self text:ch?@"R":@"L" x:16 y:y+3 color:NSColor.lightGrayColor size:11];
        for(int seg=0;seg<60;++seg) {
            float db=-60+seg;
            NSColor* color=db>=-3?NSColor.systemRedColor:(db>=-12?NSColor.systemYellowColor:NSColor.systemGreenColor);
            [(db<level[ch]?color:[NSColor colorWithWhite:0.16 alpha:1]) setFill];
            NSRectFill(NSMakeRect(x+seg*width/60.,y,width/60.-1.5,20));
        }
        if(hold[ch]>-60) { [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(x+std::clamp((hold[ch]+60)/60.f,0.f,1.f)*width-1,y-1,2,22)); }
        [self text:level[ch]<-60?@"−∞":[NSString stringWithFormat:@"%.1f",level[ch]] x:x+width+8 y:y+3 color:NSColor.whiteColor size:11];
        [(clip[ch]?NSColor.systemRedColor:[NSColor colorWithWhite:0.2 alpha:1]) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(self.bounds.size.width-16,y+7,6,6)] fill];
    }
    [self text:@"1.5 s HOLD  ·  CLICK TO RESET CLIP" x:16 y:132 color:NSColor.grayColor size:9];
}
@end
