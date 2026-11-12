#pragma once
#include <cstddef>
struct BlockProcessor {
    virtual ~BlockProcessor()=default;
    virtual int prepare(double rate)=0; // Only while output is stopped.
    virtual void process(float* left,float* right,size_t frames)=0;
};
