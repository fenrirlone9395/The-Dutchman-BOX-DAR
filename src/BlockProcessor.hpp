#pragma once
#include <cstddef>
struct BlockProcessor {
    virtual ~BlockProcessor()=default;
    virtual int prepare(double rate)=0; // Only while output is stopped.
    virtual void process(float* left,float* right,size_t frames)=0;
};

struct SpatialRenderer {
    virtual ~SpatialRenderer()=default;
    virtual bool blending()const=0;
    virtual int process(float* left,float* right,size_t frames,bool active,float angle)=0;
};
