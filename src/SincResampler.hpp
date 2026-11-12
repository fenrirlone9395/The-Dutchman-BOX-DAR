#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>
#include <stdexcept>
#include <vector>

// All table allocation and transcendental work happens in prepare(), never render().
// Float32 transport; double local accumulation does not change the engine/AU format.
class SincResampler {
    static constexpr size_t phases=2048;
    std::vector<float> table;
    size_t length=0;
    static double i0(double x) {double sum=1,term=1;for(int k=1;k<80;++k){term*=x*x/(4*k*k);sum+=term;if(term<sum*1e-16)break;}return sum;}
public:
    void prepare(double inputRate,double outputRate) {
        if(!std::isfinite(inputRate)||!std::isfinite(outputRate)||inputRate<8000||outputRate<8000||inputRate>192000||outputRate>192000)throw std::invalid_argument("Unsupported rate");
        double ratio=inputRate/outputRate;
        length=size_t(std::ceil(1024*std::max(1.,ratio)/32))*32;
        if(length>8192)throw std::invalid_argument("Sinc table budget exceeded for this rate pair; use Legacy");
        table.resize((phases+1)*length);
        // Passband/stopband transition centered at 99% of the lower Nyquist.
        // Guard against the full +/-1000ppm ASRC ratio range.
        double cutoff=.99*std::min(1.,1/(ratio*1.001)),beta=12,normal=i0(beta);
        for(size_t p=0;p<=phases;++p){
            double fraction=double(p)/phases,sum=0;
            for(size_t k=0;k<length;++k){
                double x=double(k)-double(length/2-1)-fraction;
                double window=i0(beta*std::sqrt(std::max(0.,1-std::pow(x/(length/2),2))))/normal;
                double c=(std::abs(x)<1e-15?cutoff:std::sin(std::numbers::pi*cutoff*x)/(std::numbers::pi*x))*window;
                table[p*length+k]=float(c);sum+=c;
            }
            for(size_t k=0;k<length;++k)table[p*length+k]/=sum;
        }
    }
    size_t taps()const{return length;}
    size_t lookahead()const{return length/2;}
    size_t bytes()const{return table.size()*sizeof(float);}
    template<class Reader> std::array<float,2> at(uint64_t position,double fraction,const Reader& reader)const {
        double f=fraction*phases;size_t p=std::min(size_t(f),phases-1);float blend=float(f-p);
        const float* a=table.data()+p*length;const float* b=a+length;
        double l=0,r=0;
        // Reader provides zero for startup history before frame zero.
        for(size_t k=0;k<length;++k){
            int64_t index=int64_t(position)+int64_t(k)-int64_t(length/2-1);
            auto sample=reader(index);double c=a[k]+double(blend)*(b[k]-a[k]);
            l+=sample[0]*c;r+=sample[1]*c;
        }
        return {float(l),float(r)};
    }
};
