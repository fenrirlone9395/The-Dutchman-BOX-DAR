#import "Theme.h"
#include <initializer_list>
#include <cmath>
@implementation DARButton
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame])){self.bezelStyle=NSBezelStyleRounded;self.bordered=NO;self.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];}return self;}
- (NSSize)intrinsicContentSize {NSSize text=self.attributedTitle.length?self.attributedTitle.size:[self.title sizeWithAttributes:DARTextAttributes(12,NSColor.whiteColor)];return NSMakeSize(MAX(28,text.width+24),28);}
- (void)drawRect:(NSRect)dirty {
    NSRect rect=NSInsetRect(self.bounds,1,1);NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5];
    NSColor* top=self.primary?DARColor(0xA91C34):DARColor(0x244368);NSColor* bottom=self.primary?DARColor(0x631125):DARColor(0x0B1C34);
    if(self.highlighted){top=DARAmber();bottom=DARColor(0x80510E);}
    [[[NSGradient alloc] initWithStartingColor:top endingColor:bottom] drawInBezierPath:shape angle:90];
    [(self.primary?DARColor(0xD64450):DARColor(0x506582)) setStroke];shape.lineWidth=1;[shape stroke];
    NSAttributedString* title=self.attributedTitle;
    NSDictionary* attributes=DARTextAttributes(12,self.enabled?NSColor.whiteColor:DARColor(0x6E8099));
    if(title.length) {
        NSMutableAttributedString* styled=[title mutableCopy];[styled addAttribute:NSForegroundColorAttributeName value:self.enabled?NSColor.whiteColor:DARColor(0x6E8099) range:NSMakeRange(0,styled.length)];
        NSSize size=styled.size;[styled drawAtPoint:NSMakePoint(self.alignment==NSTextAlignmentLeft?12:(self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2)];
    } else {
        NSSize size=[self.title sizeWithAttributes:attributes];[self.title drawAtPoint:NSMakePoint(self.alignment==NSTextAlignmentLeft?12:(self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2) withAttributes:attributes];
    }
}
@end
@implementation DARFaceplate
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {
    NSRect r=NSInsetRect(self.bounds,1,1);NSBezierPath* p=[NSBezierPath bezierPathWithRoundedRect:r xRadius:7 yRadius:7];
    [[[NSGradient alloc] initWithStartingColor:DARColor(0x19365C) endingColor:DARColor(0x0A1D38)] drawInBezierPath:p angle:90];
    [(self.selected?DARAmber():DARColor(0x456184)) setStroke];p.lineWidth=1;[p stroke];
    if(self.selected){[DARRed() setFill];NSRectFill(NSMakeRect(55,14,3,r.size.height-28));}
    if(self.slotNumber>0) {
        DARDrawText([NSString stringWithFormat:@"%02ld",(long)self.slotNumber],NSMakePoint(20,(r.size.height-20)/2),18,DARAmber());
        for(CGFloat y: {CGFloat(10),CGFloat(r.size.height-10)}) {NSRect screw=NSMakeRect(6,y-3,6,6);[DARColor(0x64768D) setFill];[[NSBezierPath bezierPathWithOvalInRect:screw] fill];[DARDeep() setFill];NSRectFill(NSMakeRect(7,y-.5,4,1));}
    }
}
@end

@implementation DARMiniMeter
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)rect {
    for(int ch=0;ch<2;++ch){float value=ch?self.right:self.left;float db=20*log10f(fmaxf(value,1e-6));
        for(int seg=0;seg<14;seg++){float threshold=-60+seg*60./14;NSColor* color=threshold>=-4?DARRed():(threshold>=-12?DARAmber():NSColor.systemGreenColor);[(db>threshold?color:DARColor(0x25384C)) setFill];NSRectFill(NSMakeRect(seg*self.bounds.size.width/14,4+ch*10,self.bounds.size.width/14-1,6));}
    }
}
@end
