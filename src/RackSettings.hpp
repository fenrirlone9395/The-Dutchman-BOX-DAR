#pragma once
#import <Foundation/Foundation.h>
#include "DSP.hpp"
#include "SpatialDSP.hpp"
// Main-thread persistence only. Never serializes audio buffers or DSP history.
struct RackSettings {
    float inputDB=0,masterDB=0;
    std::array<float,15> bands{};
    bool eqBypass=false,limiterBypass=false,spatialEnabled=false;
    float angle=30,distance=1.5f,amount=.5f;
    static RackSettings capture(const DSPParameters& p,const SpatialParameters& s) {
        RackSettings v;v.inputDB=p.inputDB;v.masterDB=p.masterDB;
        for(size_t i=0;i<v.bands.size();++i)v.bands[i]=p.bands[i];
        v.eqBypass=p.eqBypass;v.limiterBypass=p.limiterBypass;
        v.spatialEnabled=s.enabled;v.angle=s.angle;v.distance=s.distance;v.amount=s.amount;return v;
    }
    NSDictionary* encode() const {
        NSMutableArray* gains=[NSMutableArray new];for(float gain:bands)[gains addObject:@(gain)];
        return @{@"inputDB":@(inputDB),@"masterDB":@(masterDB),@"geq":@{@"bands":gains,@"bypass":@(eqBypass)},@"limiterBypass":@(limiterBypass),@"spatial":@{@"enabled":@(spatialEnabled),@"angle":@(angle),@"distance":@(distance),@"amount":@(amount)}};
    }
    static bool number(id value,double lo,double hi,float& result) {
        if(![value isKindOfClass:NSNumber.class])return false;double n=[value doubleValue];
        if(!std::isfinite(n)||n<lo||n>hi)return false;result=float(n);return true;
    }
    static bool boolean(id value,bool& result) {
        if(![value isKindOfClass:NSNumber.class])return false;double n=[value doubleValue];if(n!=0&&n!=1)return false;result=n!=0;return true;
    }
    static bool decode(id root,RackSettings& result) {
        if(![root isKindOfClass:NSDictionary.class])return false;id eq=root[@"geq"],s=root[@"spatial"];
        if(![eq isKindOfClass:NSDictionary.class]||![s isKindOfClass:NSDictionary.class])return false;
        id gains=eq[@"bands"];if(![gains isKindOfClass:NSArray.class]||[gains count]!=15)return false;
        RackSettings v;
        if(!number(root[@"inputDB"],-24,12,v.inputDB)||!number(root[@"masterDB"],-60,6,v.masterDB)||!boolean(eq[@"bypass"],v.eqBypass)||!boolean(root[@"limiterBypass"],v.limiterBypass)||!boolean(s[@"enabled"],v.spatialEnabled)||!number(s[@"angle"],10,75,v.angle)||!number(s[@"distance"],.4f,3,v.distance)||!number(s[@"amount"],0,1,v.amount))return false;
        for(size_t i=0;i<15;++i)if(!number(gains[i],-12,12,v.bands[i]))return false;
        result=v;return true;
    }
    void apply(DSPParameters& p,SpatialParameters& s) const {
        p.inputDB=inputDB;p.masterDB=masterDB;for(size_t i=0;i<15;++i)p.bands[i]=bands[i];
        p.eqBypass=eqBypass;p.limiterBypass=limiterBypass;
        s.angle=angle;s.distance=distance;s.amount=amount;s.enabled=spatialEnabled;
    }
};
