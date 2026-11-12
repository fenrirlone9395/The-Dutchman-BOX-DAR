#include "EngineDiagnostics.hpp"
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#include <sstream>
ClockDescription describeClock(uint32_t device){
    ClockDescription d;d.device=device;std::ostringstream text;text<<"device="<<device;
    auto get=[&](AudioObjectPropertySelector selector,void* value,UInt32 size){AudioObjectPropertyAddress a{selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};return !AudioObjectGetPropertyData(device,&a,0,nullptr,&size,value);};
    if(!get(kAudioDevicePropertyNominalSampleRate,&d.nominal,sizeof(d.nominal)))text<<" nominal=Unknown";
    if(!get(kAudioDevicePropertyActualSampleRate,&d.actual,sizeof(d.actual)))text<<" actual=Unknown";
    if(!get(kAudioDevicePropertyClockDomain,&d.domain,sizeof(d.domain)))text<<" domain=Unknown";
    AudioObjectPropertyAddress source{kAudioDevicePropertyClockSource,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};UInt32 size=sizeof(d.source);
    if(AudioObjectGetPropertyData(device,&source,0,nullptr,&size,&d.source))text<<" clockSource=Unknown";else text<<" clockSource="<<d.source;
    auto cfString=[&](AudioObjectPropertySelector selector){CFStringRef s=nullptr;if(!get(selector,&s,sizeof(s))||!s)return std::string("Unknown");NSString* value=CFBridgingRelease(s);return std::string(value.UTF8String);};
    d.uid=cfString(kAudioDevicePropertyDeviceUID);d.clockDevice=cfString(kAudioDevicePropertyClockDevice);
    text<<" uid="<<d.uid<<" clockDomain="<<d.domain<<" clockDevice="<<d.clockDevice<<" nominal="<<d.nominal<<" reportedActual="<<d.actual;
    for(auto selector:{kAudioAggregateDevicePropertyFullSubDeviceList,kAudioAggregateDevicePropertyComposition}){CFTypeRef v=nullptr;if(get(selector,&v,sizeof(v))&&v){id object=CFBridgingRelease(v);text<<" aggregate="<<[[object description] UTF8String];}}
    d.details=text.str();return d;
}

bool clockConfigurationMatches(const ClockDescription& before){
    if(!before.device)return false;
    auto get=[&](AudioObjectPropertySelector selector,void* value,UInt32 size){AudioObjectPropertyAddress a{selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};return !AudioObjectGetPropertyData(before.device,&a,0,nullptr,&size,value);};
    double rate=0;uint32_t domain=0,source=0;
    if(!get(kAudioDevicePropertyNominalSampleRate,&rate,sizeof(rate))||rate!=before.nominal)return false;
    if(get(kAudioDevicePropertyClockDomain,&domain,sizeof(domain))&&domain!=before.domain)return false;
    if(get(kAudioDevicePropertyClockSource,&source,sizeof(source))&&source!=before.source)return false;
    return true;
}
