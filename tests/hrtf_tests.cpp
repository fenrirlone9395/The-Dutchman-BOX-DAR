#include "../src/HRTFRenderer.hpp"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <numeric>
#include <vector>

struct Response {
    std::vector<float> left,right;
    double averageUS=0,maximumUS=0;
};
static Response impulse(double rate,bool rightSource,float angle){
    HRTFRenderer renderer;assert(renderer.prepare(rate)==noErr);
    std::array<float,512> left{},right{};
    // Settle the angle and wet ramp before measuring the mixer response.
    for(int i=0;i<80;++i)assert(renderer.process(left.data(),right.data(),512,true,angle)==noErr);
    Response result;
    for(int block=0;block<32;++block){
        left.fill(0);right.fill(0);
        if(!block)(rightSource?right:left)[0]=.25f;
        auto start=std::chrono::steady_clock::now();
        assert(renderer.process(left.data(),right.data(),512,true,angle)==noErr);
        double us=std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-start).count();
        result.averageUS+=us/32;result.maximumUS=std::max(result.maximumUS,us);
        result.left.insert(result.left.end(),left.begin(),left.end());
        result.right.insert(result.right.end(),right.begin(),right.end());
    }
    for(int i=0;i<16;++i)assert(renderer.process(left.data(),right.data(),512,false,angle)==noErr);
    assert(!renderer.blending());
    left.fill(.25f);right.fill(-.125f);
    assert(renderer.process(left.data(),right.data(),512,false,angle)==noErr);
    for(int i=0;i<512;++i)assert(left[i]==.25f&&right[i]==-.125f);
    return result;
}
static double energy(const std::vector<float>& x){return std::inner_product(x.begin(),x.end(),x.begin(),0.0);}
static size_t peak(const std::vector<float>& x){return std::max_element(x.begin(),x.end(),[](auto a,auto b){return std::abs(a)<std::abs(b);})-x.begin();}
int main(){
    for(double rate:{44100.,48000.,96000.,192000.}){
        auto l=impulse(rate,false,30),r=impulse(rate,true,30),wide=impulse(rate,false,65);
        assert(energy(l.left)>energy(l.right)&&energy(l.right)>1e-8);
        assert(energy(r.right)>energy(r.left)&&energy(r.left)>1e-8);
        assert(l.left!=wide.left&&l.right!=wide.right);
        assert(peak(l.left)<l.left.size()/2&&peak(r.right)<r.right.size()/2);
        printf("%.0f Hz: left speaker ear energies %.6g/%.6g, right %.6g/%.6g; near/far peaks %zu/%zu samples; 512-frame mixer mean %.1f/max %.1f us\n",rate,energy(l.left),energy(l.right),energy(r.left),energy(r.right),peak(l.left),peak(l.right),l.averageUS,l.maximumUS);
    }
    puts("PASS: two directional responses, angle control, finite rendering and exact dry output after switch-off");
}
