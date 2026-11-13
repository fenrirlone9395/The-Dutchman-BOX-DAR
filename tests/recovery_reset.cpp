#include "../src/ClockRateAdapter.hpp"
#include <cassert>
#include <cstdio>
int main(){ClockRateAdapter a;a.prepare(48000,48000,{});auto reader=[](int64_t){return std::array<float,2>{.125f,-.125f};};uint64_t w=2048;float l,r;
// Accumulate nonzero controller history with a long elevated queue, without rendering.
for(int i=0;i<10000;++i)a.begin(w+1500,512,1.2);
assert(a.telemetry.ppm>100);auto before=a.telemetry.recoveries.load();
a.begin(12000,512,1.2);assert(a.telemetry.recoveries==before+1);assert(a.consumed()==12000-a.targetFill());assert(a.telemetry.filteredFill==double(a.targetFill()));assert(std::abs(a.telemetry.ppm.load())<.11);
// Consume until starvation, then re-prime; stale PI correction must not return.
for(int b=0;b<6;++b){a.begin(12000,512,1.2);for(int i=0;i<512;++i)a.next(12000,i,512,reader,l,r);}
assert(!a.isPrimed());w=a.consumed()+2048;a.begin(w,512,1.2);assert(a.isPrimed());assert(std::abs(a.telemetry.ppm.load())<.11);assert(a.telemetry.filteredFill==2048-a.fractionalPosition());
puts("PASS: backlog reposition uses current queue fill; backlog/starvation re-prime clears stale PI and slew history");}
