#pragma once
#include "AURack.hpp"
struct VST3Choice { std::string path, cid, name; };
// Cache reads on main; scan runs on a background queue. Each bundle probe is isolated.
std::vector<VST3Choice> scanVST3Effects(std::string& report,bool force=true);
std::vector<VST3Choice> cachedVST3Effects();
int runVST3Probe(const char* path);
class VST3Effect final : public RackEffect {
    struct Impl;
    std::unique_ptr<Impl> impl;
public:
    VST3Choice vst;
    explicit VST3Effect(VST3Choice);
    ~VST3Effect() override;
    OSStatus prepare(double) override;
    void process(float*,float*,UInt32) override;
    double latency() const override;
    CFPropertyListRef copyState() const override;
    OSStatus restore(CFPropertyListRef) override;
    const char* errorDetail() const override;
    bool isVST3() const override { return true; }
    bool showEditor() override;
    void closeEditor() override;
    void idle() override;
};
