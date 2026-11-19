#import "SpatialView.h"
#import "Theme.h"
#include <numbers>
@implementation DARSpatialView {
    SpatialParameters* parameters;
    NSInteger dragging;
    NSPoint last;
}
- (instancetype)initWithParameters:(SpatialParameters*)p {if((self=[super initWithFrame:NSZeroRect])){parameters=p;dragging=0;self.toolTip=@"スピーカー上でホイール：角度 / ドラッグ：角度・距離 / 中央のリングを上下ドラッグ：Crossfeed Amount / ダブルクリック：初期配置";self.accessibilityLabel=@"Crossfeed sound field";}return self;}
- (BOOL)isFlipped{return YES;}
- (NSPoint)projectX:(double)x depth:(double)z {return NSMakePoint(self.bounds.size.width/2+x*120/(1+.25*z),self.bounds.size.height-92-z*135/(1+.25*z));}
- (std::atomic<float>&)speakerAngle {return parameters->hrtf?parameters->hrtfAngle:parameters->angle;}
- (NSPoint)speaker:(NSInteger)side {double angle=[self speakerAngle].load()*std::numbers::pi/180,d=parameters->hrtf?1.5:parameters->distance.load();return [self projectX:side*d*sin(angle) depth:d*cos(angle)];}
- (void)resetField {[self speakerAngle]=parameters->hrtf?SpatialParameters::defaultHRTFAngle:30;if(!parameters->hrtf){parameters->distance=1.5;parameters->amount=.5;}self.needsDisplay=YES;}
- (void)line:(NSPoint)a to:(NSPoint)b color:(NSColor*)color width:(CGFloat)width {NSBezierPath* path=[NSBezierPath bezierPath];[path moveToPoint:a];[path lineToPoint:b];[color setStroke];path.lineWidth=width;[path stroke];}
- (void)drawRect:(NSRect)dirty {
    [DARDeep() setFill];NSRectFill(self.bounds);
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    const bool hrtf=parameters->hrtf;
    DARDrawText(hrtf?@"HRTF / VIRTUAL SPEAKERS":@"SPATIAL LISTENING / CROSSFEED",NSMakePoint(22,14),15,NSColor.whiteColor);
    DARDrawText(parameters->enabled?@"● ACTIVE":@"○ BYPASS",NSMakePoint(w-160,16),12,parameters->enabled?DARAmber():NSColor.grayColor);
    for(double z=0;z<=3;z+=.5)[self line:[self projectX:-3 depth:z] to:[self projectX:3 depth:z] color:DARColor(0x233D5D) width:1];
    for(double x=-3;x<=3;x+=.5)[self line:[self projectX:x depth:0] to:[self projectX:x depth:3] color:DARColor(0x233D5D) width:1];
    NSPoint head=[self projectX:0 depth:0];
    for(NSInteger side:{-1,1}) {
        NSPoint speaker=[self speaker:side];
        [self line:head to:speaker color:DARAmber() width:2];
        [self line:NSMakePoint(head.x-side*13,head.y) to:speaker color:DARColor(0xB51F35) width:1];
        NSBezierPath* shadow=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(speaker.x-30,speaker.y+14,60,12)];[DARColor(0x050F20) setFill];[shadow fill];
        NSRect box=NSMakeRect(speaker.x-25,speaker.y-38,50,60);
        [[[NSGradient alloc] initWithStartingColor:DARColor(0x35567C) endingColor:DARNavy()] drawInRect:box angle:90];
        [DARAmber() setStroke];NSFrameRect(box);
        for(int i=0;i<2;i++){NSRect cone=NSMakeRect(speaker.x-(i?13:7),speaker.y-(i?4:28),i?26:14,i?26:14);[DARDeep() setFill];[[NSBezierPath bezierPathWithOvalInRect:cone] fill];[DARColor(0x64768D) setStroke];[[NSBezierPath bezierPathWithOvalInRect:cone] stroke];}
        DARDrawText(side<0?@"L":@"R",NSMakePoint(speaker.x-5,speaker.y-58),12,DARAmber());
    }
    NSRect ring=NSMakeRect(head.x-38,head.y-24,76,48);[DARColor(0x19365C) setFill];[[NSBezierPath bezierPathWithOvalInRect:ring] fill];[DARAmber() setStroke];NSBezierPath* outline=[NSBezierPath bezierPathWithOvalInRect:ring];outline.lineWidth=hrtf?2:2+parameters->amount.load()*5;[outline stroke];
    DARDrawText(@"YOU",NSMakePoint(head.x-12,head.y-7),12,NSColor.whiteColor);
    DARDrawText(hrtf?[NSString stringWithFormat:@"ANGLE ±%.0f°",[self speakerAngle].load()]:[NSString stringWithFormat:@"ANGLE ±%.0f°    DISTANCE %.2f m    AMOUNT %.0f%%",[self speakerAngle].load(),parameters->distance.load(),parameters->amount.load()*100],NSMakePoint(28,h-48),12,DARAmber());
    DARDrawText(hrtf?@"Drag or scroll over either speaker: linked angle":@"Drag: angle / distance · Scroll over speaker: angle · Ring: amount",NSMakePoint(28,h-27),10,NSColor.lightGrayColor);
    DARDrawText(hrtf?@"Headphones · two virtual speakers":@"Headphones · geometric crossfeed",NSMakePoint(22,42),10,NSColor.grayColor);
}
- (void)mouseDown:(NSEvent*)event {
    if(event.clickCount==2){[self resetField];return;}
    last=[self convertPoint:event.locationInWindow fromView:nil];NSPoint left=[self speaker:-1],right=[self speaker:1],head=[self projectX:0 depth:0];
    if(std::hypot(last.x-left.x,last.y-left.y)<60)dragging=-1;
    else if(std::hypot(last.x-right.x,last.y-right.y)<60)dragging=1;
    else if(!parameters->hrtf&&std::hypot(last.x-head.x,last.y-head.y)<50)dragging=2;else dragging=0;
}
- (void)mouseDragged:(NSEvent*)event {
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    if(dragging==2)parameters->amount=std::clamp(parameters->amount.load()+float(last.y-point.y)*.005f,0.f,1.f);
    else if(dragging) {
        double depth=std::clamp(double(self.bounds.size.height-92-point.y),0.,250.);
        double z=std::max(.05,depth/(135-.25*depth)),x=std::abs(point.x-self.bounds.size.width/2)*(1+.25*z)/120;
        [self speakerAngle]=std::clamp(float(std::atan2(x,z)*180/std::numbers::pi),10.f,75.f);
        if(!parameters->hrtf)parameters->distance=std::clamp(float(std::hypot(x,z)),.4f,3.f);
    }
    last=point;self.needsDisplay=YES;
}
- (void)scrollWheel:(NSEvent*)event {
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    NSPoint left=[self speaker:-1],right=[self speaker:1];
    if(std::hypot(point.x-left.x,point.y-left.y)>60 && std::hypot(point.x-right.x,point.y-right.y)>60){
        [super scrollWheel:event];return;
    }
    if(event.momentumPhase!=NSEventPhaseNone)return;
    const double delta=event.scrollingDeltaY;
    if(!std::isfinite(delta)||delta==0)return;
    const double step=(event.hasPreciseScrollingDeltas?.25:2)*(event.modifierFlags&NSEventModifierFlagShift?.2:1);
    auto& angle=[self speakerAngle];
    angle=std::clamp(float(angle.load()+delta*step),10.f,75.f);
    self.needsDisplay=YES;
}
- (void)mouseUp:(NSEvent*)event {dragging=0;}
@end
