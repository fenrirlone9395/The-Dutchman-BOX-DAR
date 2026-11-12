#import "RackControls.h"
#import "Theme.h"
#import "DrawText.h"
#include <complex>
static NSColor* shade(CGFloat v) { return [NSColor colorWithWhite:v alpha:1]; }
static void label(NSString* s,CGFloat x,CGFloat y,CGFloat size,NSColor* c) {
    DARDrawText(s,NSMakePoint(x,y),size,c);
}
@implementation DARGraphicEQ { DSPParameters* p; NSInteger band; }
- (instancetype)initWithParameters:(DSPParameters*)value { if((self=[super initWithFrame:NSZeroRect])) {p=value;self.sampleRate=48000;band=-1;self.toolTip=@"ドラッグ：±12 dB / Shift：微調整 / ダブルクリック：0 dB / 左右キー：バンド選択 / 上下キー：調整"; self.accessibilityLabel=@"15 band Master Graphic EQ";}return self; }
- (BOOL)isFlipped {return YES;}
- (BOOL)acceptsFirstResponder {return YES;}
- (CGFloat)column {return (self.bounds.size.width-80)/15;}
- (void)flatten {for(auto& v:p->bands)v=0;self.needsDisplay=YES;}
- (void)drawRect:(NSRect)dirty {
    CGFloat width=self.bounds.size.width, column=self.column;
    [DARDeep() setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    if(!self.compact)label(@"MASTER GRAPHIC EQ",16,10,12,shade(.9)); if(!self.compact)label(@"15 BANDS   /   ±12 dB",width-180,12,10,shade(.5));
    NSRect graph=self.compact?NSInsetRect(self.bounds,4,4):NSMakeRect(44,32,width-72,48); [shade(.035) setFill]; NSRectFill(graph);
    NSBezierPath* curve=[NSBezierPath bezierPath];
    for(int n=0;n<=500;n++) {
        double rate=MAX(8000,self.sampleRate);
        double hz=20*pow(1000.,n/500.),mag=1;
        std::complex<double> z=std::polar(1.,-2*std::numbers::pi*hz/rate);
        for(size_t i=0;i<15;i++) {
            double A=pow(10.,p->bands[i].load()/40.),w=2*std::numbers::pi*std::min(double(DSPParameters::centers[i]),rate*.45)/rate,a=sin(w)/(2*2.14);
            mag*=std::abs(((1+a*A)-2*cos(w)*z+(1-a*A)*z*z)/((1+a/A)-2*cos(w)*z+(1-a/A)*z*z));
        }
        if(p->eqBypass.load())mag=1;
        NSPoint pt=NSMakePoint(graph.origin.x+n/500.*graph.size.width,graph.origin.y+graph.size.height/2-std::clamp(20*log10(std::max(mag,1e-9)),-18.,18.)*(graph.size.height/40));
        if(n==0)[curve moveToPoint:pt];else [curve lineToPoint:pt];
    }
    [shade(.25) setStroke]; NSBezierPath* zero=[NSBezierPath bezierPath]; [zero moveToPoint:NSMakePoint(graph.origin.x,NSMidY(graph))];[zero lineToPoint:NSMakePoint(NSMaxX(graph),NSMidY(graph))];[zero stroke];
    [DARAmber() setStroke];curve.lineWidth=1.5;[curve stroke];
    if(self.compact)return;
    for(int db=-12;db<=12;db+=3) {
        CGFloat y=145-db*3.7;
        [shade(db==0?.48:.21) setFill];NSRectFill(NSMakeRect(42,y,width-70,db==0?1:0.5));
        label([NSString stringWithFormat:@"%+d",db],12,y-5,9,shade(.55));
    }
    for(int i=0;i<15;i++) {
        CGFloat x=44+(i+.5)*column;float value=p->bands[i].load();CGFloat y=145-value*3.7;
        [shade(.015) setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x-2,98,4,94) xRadius:2 yRadius:2] fill];
        [shade(.23) setStroke];NSFrameRect(NSMakeRect(x-3,97,6,96));
        NSRect cap=NSMakeRect(x-12,y-5,24,10);
        NSGradient* metal=[[NSGradient alloc] initWithStartingColor:shade(i==band?.85:.64) endingColor:shade(.24)]; [metal drawInRect:cap angle:90];
        [shade(.06) setFill];NSRectFill(NSMakeRect(x-10,y,20,1));
        float hz=DSPParameters::centers[i];NSString* freq=hz>=1000?[NSString stringWithFormat:@"%gk",hz/1000]:[NSString stringWithFormat:@"%.0f",hz];
        label(freq,x-14,199,10,shade(.77));label([NSString stringWithFormat:@"%+.1f",value],x-14,216,9,i==band?DARAmber():shade(.5));
    }
}
- (void)mouseDown:(NSEvent*)e {
    if(self.compact){[self sendAction:self.action to:self.target];return;}
    [self.window makeFirstResponder:self];NSPoint pt=[self convertPoint:e.locationInWindow fromView:nil];
    band=std::clamp(NSInteger((pt.x-44)/self.column),NSInteger(0),NSInteger(14));
    if(e.clickCount==2)p->bands[band]=0;else if(pt.y>=90)[self mouseDragged:e];self.needsDisplay=YES;
}
- (void)mouseDragged:(NSEvent*)e {
    if(band<0)return;NSPoint pt=[self convertPoint:e.locationInWindow fromView:nil];
    float value=(145-pt.y)/3.7;
    if(e.modifierFlags&NSEventModifierFlagShift)value=p->bands[band].load()-e.deltaY*.05;
    p->bands[band]=std::round(std::clamp(value,-12.f,12.f)*10)/10;self.needsDisplay=YES;
}
- (void)keyDown:(NSEvent*)e {if(band<0)band=0; if(e.keyCode==123)band=MAX(0,band-1);else if(e.keyCode==124)band=MIN(14,band+1);else if(e.keyCode==125||e.keyCode==126)p->bands[band]=std::clamp(p->bands[band].load()+(e.keyCode==126?.5f:-.5f),-12.f,12.f);else { [super keyDown:e];return;}self.needsDisplay=YES;}
@end
@implementation DARGainKnob { float knobValue; }
- (float)floatValue { return knobValue; }
- (instancetype)initWithFrame:(NSRect)frame { if((self=[super initWithFrame:frame]))self.cell=[NSActionCell new];return self;}
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstResponder{return YES;}
- (void)setFloatValue:(float)value {knobValue=std::clamp(value,_minimum,_maximum);self.needsDisplay=YES;}
- (void)drawRect:(NSRect)r {
    CGFloat x=self.bounds.size.width/2,y=54;
    label(self.caption?:@"GAIN",8,8,11,shade(.7));
    NSBezierPath* circle=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x-28,y-28,56,56)];
    [[[NSGradient alloc] initWithStartingColor:shade(.37) endingColor:shade(.12)] drawInBezierPath:circle angle:90];[shade(.5) setStroke];circle.lineWidth=1;[circle stroke];
    double angle=(225-270*(self.floatValue-self.minimum)/(self.maximum-self.minimum))*std::numbers::pi/180;
    NSBezierPath* mark=[NSBezierPath bezierPath];[mark moveToPoint:NSMakePoint(x+cos(angle)*16,y-sin(angle)*16)];[mark lineToPoint:NSMakePoint(x+cos(angle)*24,y-sin(angle)*24)];[DARAmber() setStroke];mark.lineWidth=3;[mark stroke];
    label([NSString stringWithFormat:@"%+.1f dB",self.floatValue],x-32,91,12,shade(.95));
}
- (void)mouseDown:(NSEvent*)e {[self.window makeFirstResponder:self];if(e.clickCount==2){self.floatValue=0;[self sendAction:self.action to:self.target];}}
- (void)mouseDragged:(NSEvent*)e {self.floatValue-=e.deltaY*((e.modifierFlags&NSEventModifierFlagShift)?.02:.15);[self sendAction:self.action to:self.target];}
- (void)scrollWheel:(NSEvent*)event {
    if(!self.enabled || event.momentumPhase!=NSEventPhaseNone)return;
    CGFloat delta=event.scrollingDeltaY;
    if(!std::isfinite(delta) || delta==0)return;
    // A wheel step is 0.5 dB; precise trackpad scrolling uses a pixel-scale rate.
    // Ignore momentum so gain changes stop when the fingers leave the trackpad.
    float step=event.hasPreciseScrollingDeltas?.02f:.5f;
    if(event.modifierFlags&NSEventModifierFlagShift)step*=.1f;
    float before=self.floatValue;
    self.floatValue=before+delta*step;
    if(self.floatValue!=before)[self sendAction:self.action to:self.target];
}
- (void)keyDown:(NSEvent*)e {if(e.keyCode==125||e.keyCode==126){self.floatValue+=(e.keyCode==126?.5:-.5);[self sendAction:self.action to:self.target];}else [super keyDown:e];}
@end
