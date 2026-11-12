#include "../src/TapInput.hpp"
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>
#include <cassert>
#include <iostream>
#include <vector>
int main() { @autoreleasepool {
    CATapDescription* description=[[CATapDescription alloc] initExcludingProcesses:@[@123] andDeviceUID:@"test-device" withStream:0];
    description.mixdown=NO;
    assert(!description.isMixdown && description.isExclusive && description.stream.integerValue==0);
    for(unsigned channels:{2u,4u,8u,16u}) {
        AudioBridge bridge;bridge.muted=false;
        std::vector<float> data(4096*channels, .75f);
        for(int i=0;i<4096;++i){data[i*channels]=.125f;data[i*channels+1]=-.25f;}
        AudioBufferList list{1,{{channels,UInt32(data.size()*sizeof(float)),data.data()}}};
        assert(pushTapStereo(bridge,&list));
        float l[512]{},r[512]{};bridge.render(l,r,512,48000);
        assert(std::abs(l[511]-.125f)<1e-6 && std::abs(r[511]+.25f)<1e-6);
        // No gain correction or averaging of the other live hardware channels.
    }
    struct Planar {UInt32 count;AudioBuffer buffers[8];} list{8,{}};
    std::vector<float> left(4096,.125f),right(4096,-.25f),other(4096,.75f);
    for(auto& b:list.buffers)b={1,UInt32(other.size()*sizeof(float)),other.data()};
    list.buffers[0].mData=left.data();list.buffers[1].mData=right.data();
    AudioBridge bridge;bridge.muted=false;
    assert(pushTapStereo(bridge,reinterpret_cast<AudioBufferList*>(&list)));
    float l[512]{},r[512]{};bridge.render(l,r,512,48000);
    assert(std::abs(l[511]-.125f)<1e-6 && std::abs(r[511]+.25f)<1e-6);
    assert(!pushTapStereo(bridge,nullptr));list.count=0;
    assert(!pushTapStereo(bridge,reinterpret_cast<AudioBufferList*>(&list)));
    list.count=8;list.buffers[0].mData=nullptr;
    assert(!pushTapStereo(bridge,reinterpret_cast<AudioBufferList*>(&list)));
    std::cout<<"PASS: non-mixdown exclusive device tap; original stereo level on 2/4/8/16-channel interleaved and 8-channel planar input; invalid buffers rejected\n";
} }
