#include "../../src/plugins/VST3Catalog.hpp"
#include <cassert>
#include <cstdio>
int main(){@autoreleasepool{
 NSURL* temp=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];NSString* root=temp.path;NSURL* cache=[temp URLByAppendingPathComponent:@"cache.plist"];
 auto bundle=[&](NSString* name){NSString* p=[root stringByAppendingPathComponent:name];[NSFileManager.defaultManager createDirectoryAtPath:[p stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:nil];[@"binary" writeToFile:[p stringByAppendingPathComponent:@"Contents/MacOS/Effect"] atomically:YES encoding:NSUTF8StringEncoding error:nil];return p;};
 NSString* a=bundle(@"A.vst3");int calls=0;std::string report;
 VST3Catalog::Probe probe=[&](NSString* path)->NSArray*{++calls;if([path.lastPathComponent isEqual:@"Bad.vst3"])return nil;return @[@{@"path":path,@"cid":@"424F5854455354310102030405060708",@"name":path.lastPathComponent}];};
 assert(VST3Catalog::cached(cache).empty());auto choices=VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==1&&choices.size()==1);assert(VST3Catalog::cached(cache).size()==1);
 VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==1);
 [@"changed binary" writeToFile:[a stringByAppendingPathComponent:@"Contents/MacOS/Effect"] atomically:YES encoding:NSUTF8StringEncoding error:nil];VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==2);
 NSString* b=bundle(@"B.vst3");choices=VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==3&&choices.size()==2);
 [NSFileManager.defaultManager removeItemAtPath:b error:nil];choices=VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==3&&choices.size()==1);
 bundle(@"Bad.vst3");VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==4);VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==4);
 VST3Catalog::scan(@[root],cache,true,probe,report);assert(calls==6);
 [@"broken cache" writeToURL:cache atomically:YES encoding:NSUTF8StringEncoding error:nil];assert(VST3Catalog::cached(cache).empty());VST3Catalog::scan(@[root],cache,false,probe,report);assert(calls==8);
 [NSFileManager.defaultManager removeItemAtURL:temp error:nil];puts("PASS: instant cache read, unchanged skip, nested binary update, new/deleted bundle, failed-probe cache, manual force, corrupt-cache recovery");
}}
