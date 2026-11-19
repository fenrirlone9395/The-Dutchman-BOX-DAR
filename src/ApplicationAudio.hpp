#pragma once
#import <AppKit/AppKit.h>
#include <CoreAudio/CoreAudio.h>
#include <libproc.h>
#include <unistd.h>
#include <vector>

inline bool sameAudioBundle(NSString* main,NSString* candidate){
    return main.length && ([main isEqualToString:candidate] || [candidate hasPrefix:[main stringByAppendingString:@"."]]);
}

inline NSString* applicationAudioBundleFamily(NSString* identifier){
    for(NSString* browser in @[@"com.google.Chrome",@"org.chromium.Chromium",@"com.microsoft.edgemac",@"com.operasoftware.Opera"])
        if(sameAudioBundle(browser,identifier))return browser;
    return identifier;
}

inline NSString* chromiumPWAParent(NSString* identifier){
    for(NSString* browser in @[@"com.google.Chrome",@"org.chromium.Chromium",@"com.microsoft.edgemac",@"com.operasoftware.Opera"]){
        if(!sameAudioBundle(browser,identifier))continue;
        NSRange suffix=[identifier rangeOfString:@".app."];
        if(suffix.location!=NSNotFound)return [identifier substringToIndex:suffix.location];
    }
    return nil;
}

// A PWA's window belongs to its launcher; audio belongs to the hosting browser.
inline NSRunningApplication* applicationAudioOwner(NSRunningApplication* application){
    if(!application || application.terminated || application.processIdentifier==getpid())return nil;
    NSString* browser=chromiumPWAParent(application.bundleIdentifier);
    if(!browser)return application;
    NSArray<NSRunningApplication*>* hosts=[NSRunningApplication runningApplicationsWithBundleIdentifier:browser];
    if(hosts.count!=1 || hosts.firstObject.terminated)return nil;
    return hosts.firstObject;
}

inline bool audioProcessDescendsFrom(pid_t candidate,pid_t parent){
    if(candidate<=0 || parent<=0 || candidate==getpid())return false;
    for(unsigned depth=0;depth<32 && candidate>1;++depth){
        if(candidate==parent)return true;
        proc_bsdinfo info{};
        if(proc_pidinfo(candidate,PROC_PIDTBSDINFO,0,&info,sizeof(info))!=sizeof(info) ||
           info.pbi_ppid==unsigned(candidate))return false;
        candidate=pid_t(info.pbi_ppid);
    }
    return false;
}

struct ApplicationAudioTargets {
    std::vector<AudioObjectID> processes;
    size_t matched=0,active=0;
    bool resolved=false;
};

inline ApplicationAudioTargets applicationAudioProcesses(NSRunningApplication* application){
    NSRunningApplication* owner=applicationAudioOwner(application);
    if(!owner)return {};
    const AudioObjectPropertyAddress list{kAudioHardwarePropertyProcessObjectList,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&list,0,nullptr,&bytes))return {};
    ApplicationAudioTargets matched;
    matched.resolved=true;
    if(!bytes)return matched;
    std::vector<AudioObjectID> objects(bytes/sizeof(AudioObjectID));
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&list,0,nullptr,&bytes,objects.data()))return {};
    objects.resize(bytes/sizeof(AudioObjectID));
    const AudioObjectPropertyAddress pidAddress{kAudioProcessPropertyPID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    const AudioObjectPropertyAddress bundleAddress{kAudioProcessPropertyBundleID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    const AudioObjectPropertyAddress outputAddress{kAudioProcessPropertyIsRunningOutput,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    for(auto object:objects){
        pid_t candidate=0;UInt32 size=sizeof(candidate);
        if(AudioObjectGetPropertyData(object,&pidAddress,0,nullptr,&size,&candidate) ||
           !audioProcessDescendsFrom(candidate,owner.processIdentifier))continue;
        // The main PID is definitive. Helpers must also identify as the app's bundle family.
        if(candidate!=owner.processIdentifier){
            CFStringRef value=nullptr;size=sizeof(value);
            if(AudioObjectGetPropertyData(object,&bundleAddress,0,nullptr,&size,&value) || !value)continue;
            NSString* bundle=CFBridgingRelease(value);
            if(!sameAudioBundle(applicationAudioBundleFamily(owner.bundleIdentifier),bundle))continue;
        }
        ++matched.matched;
        UInt32 active=0;size=sizeof(active);
        // HAL also lists app clients with no running output. On macOS 14,
        // including those clients can make an inclusive tap deliver silence.
        // Re-sampling this list on the control thread tracks output recreation.
        if(AudioObjectGetPropertyData(object,&outputAddress,0,nullptr,&size,&active) || !active)continue;
        matched.processes.push_back(object);
        ++matched.active;
    }
    return matched;
}


// WebKit's XPC audio clients may be launched by launchd and use shared bundle
// identifiers. Expose their system labels for explicit selection.
inline NSArray<NSRunningApplication*>* webkitAudioApplications(){
    AudioObjectPropertyAddress address{kAudioHardwarePropertyProcessObjectList,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&address,0,nullptr,&bytes) || !bytes)return @[];
    std::vector<AudioObjectID> objects(bytes/sizeof(AudioObjectID));
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,0,nullptr,&bytes,objects.data()))return @[];
    objects.resize(bytes/sizeof(AudioObjectID));
    NSMutableArray<NSRunningApplication*>* applications=[NSMutableArray new];
    for(auto object:objects){
        CFStringRef value=nullptr;bytes=sizeof(value);address.mSelector=kAudioProcessPropertyBundleID;
        if(AudioObjectGetPropertyData(object,&address,0,nullptr,&bytes,&value) || !value)continue;
        NSString* bundle=CFBridgingRelease(value);
        if(!sameAudioBundle(@"com.apple.WebKit",bundle))continue;
        pid_t pid=0;bytes=sizeof(pid);address.mSelector=kAudioProcessPropertyPID;
        if(AudioObjectGetPropertyData(object,&address,0,nullptr,&bytes,&pid) || pid<=0 || pid==getpid())continue;
        NSRunningApplication* application=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if(application && !application.terminated && ![applications containsObject:application])[applications addObject:application];
    }
    return [applications sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication* a,NSRunningApplication* b){
        return [(a.localizedName?:@"WebKit") localizedStandardCompare:(b.localizedName?:@"WebKit")];
    }];
}
