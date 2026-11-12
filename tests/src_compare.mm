// Offline only: file output, Apple converter construction and timing statistics.
#include "../src/SincResampler.hpp"
#include "../src/ClockRateAdapter.hpp"
#include <AudioToolbox/AudioToolbox.h>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>
using Stereo=std::array<float,2>;
using Clock=std::chrono::steady_clock;
struct Result{std::vector<Stereo> audio;double us=0;UInt32 leading=0,trailing=0;size_t firstInputPulled=0;};
static void check(OSStatus e,const char* s){if(e)throw std::runtime_error(std::string(s)+": "+std::to_string(e));}
struct Source {const std::vector<Stereo>* audio;size_t cursor=0;};
static OSStatus input(AudioConverterRef,UInt32* packets,AudioBufferList* data,AudioStreamPacketDescription**,void* ctx){auto& s=*static_cast<Source*>(ctx);size_t n=std::min(size_t(*packets),s.audio->size()-s.cursor);data->mNumberBuffers=1;data->mBuffers[0]={2,UInt32(n*sizeof(Stereo)),const_cast<Stereo*>(s.audio->data()+s.cursor)};s.cursor+=n;*packets=UInt32(n);return noErr;}
static Result apple(const std::vector<Stereo>& source,double inRate,double outRate){
 AudioStreamBasicDescription a{inRate,kAudioFormatLinearPCM,kAudioFormatFlagsNativeFloatPacked,8,1,8,2,32,0},b=a;b.mSampleRate=outRate;AudioConverterRef converter=nullptr;check(AudioConverterNew(&a,&b,&converter),"create Apple converter");
 struct Dispose{AudioConverterRef c;~Dispose(){AudioConverterDispose(c);}} dispose{converter};
 UInt32 complexity=kAudioConverterSampleRateConverterComplexity_Mastering,quality=kAudioConverterQuality_Max,prime=kConverterPrimeMethod_Normal;
 check(AudioConverterSetProperty(converter,kAudioConverterSampleRateConverterComplexity,sizeof(complexity),&complexity),"Mastering");check(AudioConverterSetProperty(converter,kAudioConverterSampleRateConverterQuality,sizeof(quality),&quality),"Max");check(AudioConverterSetProperty(converter,kAudioConverterPrimeMethod,sizeof(prime),&prime),"PrimeNormal");
 Result result;result.audio.resize(size_t(std::ceil(source.size()*outRate/inRate)));AudioConverterPrimeInfo info{};UInt32 bytes=sizeof(info);check(AudioConverterGetProperty(converter,kAudioConverterPrimeInfo,&bytes,&info),"prime info");result.leading=info.leadingFrames;result.trailing=info.trailingFrames;
 Source state{&source};size_t offset=0;auto begin=Clock::now();
 while(offset<result.audio.size()){UInt32 n=UInt32(std::min(size_t(256),result.audio.size()-offset));AudioBufferList list{1,{{2,n*8,result.audio.data()+offset}}};check(AudioConverterFillComplexBuffer(converter,input,&state,&n,&list,nullptr),"render Apple");if(!offset)result.firstInputPulled=state.cursor;if(!n)break;offset+=n;}
 result.us=std::chrono::duration<double,std::micro>(Clock::now()-begin).count();result.audio.resize(offset);return result;
}
static Result own(const std::vector<Stereo>& source,double inRate,double outRate,bool sincMode,bool varying=false){
 SincResampler sinc;if(sincMode)sinc.prepare(inRate,outRate);Result r;r.audio.resize(size_t(source.size()*outRate/inRate));r.leading=sincMode?UInt32(sinc.lookahead()):0;r.firstInputPulled=size_t(std::ceil(256*inRate/outRate))+r.leading+(sincMode?0:1);
 auto reader=[&](int64_t n){return n<0||uint64_t(n)>=source.size()?Stereo{0,0}:source[size_t(n)];};uint64_t position=0;double phase=0;auto start=Clock::now();
 for(size_t i=0;i<r.audio.size();++i){if(sincMode)r.audio[i]=sinc.at(position,phase,reader);else {auto x=reader(position),y=reader(position+1);r.audio[i]={float(x[0]+(y[0]-x[0])*phase),float(x[1]+(y[1]-x[1])*phase)};}
   double ppm=varying?100*std::sin(2*std::numbers::pi*(i/outRate)/70):0;phase+=inRate/outRate*(1+ppm*1e-6);auto n=uint64_t(phase);position+=n;phase-=n;
 }
 r.us=std::chrono::duration<double,std::micro>(Clock::now()-start).count();return r;
}
static void wav(const std::string& path,const std::vector<Stereo>& audio,int rate){std::ofstream f(path,std::ios::binary);auto u16=[&](uint16_t v){f.write(reinterpret_cast<char*>(&v),2);};auto u32=[&](uint32_t v){f.write(reinterpret_cast<char*>(&v),4);};f.write("RIFF",4);u32(36+audio.size()*8);f.write("WAVEfmt ",8);u32(16);u16(3);u16(2);u32(rate);u32(rate*8);u16(8);u16(32);f.write("data",4);u32(audio.size()*8);f.write(reinterpret_cast<const char*>(audio.data()),audio.size()*8);}
static std::vector<Stereo> tone(double rate,double hz,double seconds=1.2){std::vector<Stereo> x(size_t(rate*seconds));for(size_t i=0;i<x.size();++i){float v=.25*std::sin(2*std::numbers::pi*hz*i/rate);x[i]={v,-v};}return x;}
static double amplitude(const std::vector<Stereo>& y,double rate,double hz){size_t start=size_t(.3*rate),n=size_t(.5*rate);if(start+n>y.size())throw std::runtime_error("short render");double ss=0,cc=0,sc=0,ys=0,yc=0;for(size_t i=start;i<start+n;++i){double a=2*std::numbers::pi*hz*i/rate,s=sin(a),c=cos(a);ss+=s*s;cc+=c*c;sc+=s*c;ys+=y[i][0]*s;yc+=y[i][0]*c;}double d=ss*cc-sc*sc;return hypot((ys*cc-yc*sc)/d,(yc*ss-ys*sc)/d);}
static double db(double v){return 20*log10(std::max(v,1e-16));}
static int peak(const std::vector<Stereo>& a){return int(std::max_element(a.begin(),a.end(),[](auto x,auto y){return std::abs(x[0])<std::abs(y[0]);})-a.begin());}
int main(int argc,char** argv){try{
 std::string dir=argc>1?argv[1]:"build/src-comparison";std::filesystem::create_directories(dir);std::ofstream csv(dir+"/frequency.csv"),summary(dir+"/summary.csv");csv<<"in_rate,out_rate,method,kind,input_hz,measured_hz,gain_db,cpu_us_per_output_frame\n";summary<<"in_rate,out_rate,method,impulse_peak_offset_frames,leading_input_frames,trailing_input_frames,first_block_input_availability_or_pull_frames,passband_ripple_db,vs_apple_integer_aligned_max_error,vs_apple_integer_aligned_rms_error,lr_antiphase_max_error,cpu_us_per_output_frame\n";
 for(auto pair:{std::array<double,2>{44100,48000},{48000,44100},{88200,96000},{96000,48000}}){double in=pair[0],out=pair[1],nyquist=std::min(in,out)/2;
  std::vector<Stereo> multi(size_t(in*1.2));for(size_t i=0;i<multi.size();++i){double v=0;for(double f:{100.,1000.,5000.,10000.,18000.})v+=.05*sin(2*std::numbers::pi*f*i/in);multi[i]={float(v),float(-v)};}
  std::vector<Stereo> impulse(size_t(in*.25));impulse[size_t(in*.1)]={.5f,.5f};
  std::array<Result,3> outputs{own(multi,in,out,false),own(multi,in,out,true),apple(multi,in,out)};
  std::array<Result,3> impulses{own(impulse,in,out,false),own(impulse,in,out,true),apple(impulse,in,out)};
  int applePeak=peak(impulses[2].audio);
  for(int m=0;m<3;++m){std::string method=m==0?"LegacyLinear":m==1?"PolyphaseSinc":"AppleMasteringMax";std::string prefix=dir+"/"+std::to_string(int(in))+"-"+std::to_string(int(out))+"-"+method;
   wav(prefix+".wav",outputs[m].audio,int(out));wav(prefix+"-impulse.wav",impulses[m].audio,int(out));
   int offset=peak(impulses[m].audio)-applePeak;double max=0,sum=0,lr=0;size_t count=0;std::vector<Stereo> aligned;aligned.reserve(size_t(.5*out));
   for(size_t i=size_t(.3*out);i<size_t(.8*out);++i){int64_t j=int64_t(i)+offset;if(j<0||uint64_t(j)>=outputs[m].audio.size())continue;double e=outputs[m].audio[size_t(j)][0]-outputs[2].audio[i][0];max=std::max(max,std::abs(e));sum+=e*e;++count;lr=std::max(lr,std::abs(double(outputs[m].audio[size_t(j)][0])+outputs[m].audio[size_t(j)][1]));aligned.push_back(outputs[m].audio[size_t(j)]);}
   wav(prefix+"-aligned-steady.wav",aligned,int(out));double low=1e9,high=-1e9;
   for(double frac:{.001,.01,.1,.25,.5,.75,.85,.9,.92,.95,.97,.98,.99,.999}){double hz=std::round(nyquist*frac/2)*2;auto x=tone(in,hz);Result y=m==2?apple(x,in,out):own(x,in,out,m==1);double gain=db(amplitude(y.audio,out,hz)/.25);if(frac<=.9){low=std::min(low,gain);high=std::max(high,gain);}csv<<in<<','<<out<<','<<method<<",response,"<<hz<<','<<hz<<','<<gain<<','<<y.us/y.audio.size()<<'\n';}
   if(in>out){for(double frac:{1.001,1.01,1.04,1.08,1.2,1.4,1.6,1.8,1.95}){double hz=std::round(nyquist*frac/2)*2;if(hz>=in/2)continue;auto x=tone(in,hz);Result y=m==2?apple(x,in,out):own(x,in,out,m==1);double folded=std::abs(hz-out*std::round(hz/out));csv<<in<<','<<out<<','<<method<<",alias,"<<hz<<','<<folded<<','<<db(amplitude(y.audio,out,folded)/.25)<<','<<y.us/y.audio.size()<<'\n';}}
   else {double hz=std::round(in*.485/2)*2,image=in-hz;if(image<out/2){auto x=tone(in,hz);Result y=m==2?apple(x,in,out):own(x,in,out,m==1);csv<<in<<','<<out<<','<<method<<",image,"<<hz<<','<<image<<','<<db(amplitude(y.audio,out,image)/.25)<<','<<y.us/y.audio.size()<<'\n';}}
   summary<<std::setprecision(12)<<in<<','<<out<<','<<method<<','<<offset<<','<<outputs[m].leading<<','<<outputs[m].trailing<<','<<outputs[m].firstInputPulled<<','<<high-low<<','<<max<<','<<sqrt(sum/count)<<','<<lr<<','<<outputs[m].us/outputs[m].audio.size()<<'\n';
   std::cout<<in<<"->"<<out<<' '<<method<<" ripple="<<high-low<<"dB CPU="<<outputs[m].us/outputs[m].audio.size()<<"us/frame peakOffset="<<offset<<std::endl;
  }
 }
 // Ratio modulation stress: +/-100ppm, 70-second cycle, <=9ppm/s slew; full cycle plus guards. Analytic sine at actual input positions is the reference; Apple fixed-rate SRC is intentionally N/A.
 std::ofstream async(dir+"/asrc.csv");async<<"in_rate,out_rate,method,tone_hz,max_error_vs_analytic,rms_error_vs_analytic,amplitude_gain_db,cpu_us_per_frame\n";
 for(auto pair:{std::array<double,2>{44100,48000},{48000,44100}})for(double frac:{.1,.9,.98}){double in=pair[0],out=pair[1],hz=std::round(std::min(in,out)*.5*frac/2)*2;auto x=tone(in,hz,72.2);auto legacy=own(x,in,out,false,true);wav(dir+"/ASRC-Legacy-"+std::to_string(int(in))+"-"+std::to_string(int(hz))+".wav",legacy.audio,int(out));auto y=own(x,in,out,true,true);uint64_t pos=0;double phase=0,max=0,sum=0,refPower=0,outPower=0;size_t count=0;
  for(size_t i=0;i<y.audio.size();++i){if(i>size_t(out*.3)&&i<size_t(out*71.8)){double ref=.25*sin(2*std::numbers::pi*hz*(pos+phase)/in),e=y.audio[i][0]-ref;max=std::max(max,std::abs(e));sum+=e*e;refPower+=ref*ref;outPower+=y.audio[i][0]*y.audio[i][0];++count;}double ppm=100*sin(2*std::numbers::pi*(i/out)/70);phase+=in/out*(1+ppm*1e-6);auto n=uint64_t(phase);pos+=n;phase-=n;}
  async<<in<<','<<out<<",PolyphaseSinc,"<<hz<<','<<max<<','<<sqrt(sum/count)<<','<<10*log10(outPower/refPower)<<','<<y.us/y.audio.size()<<'\n';wav(dir+"/ASRC-"+std::to_string(int(in))+"-"+std::to_string(int(hz))+".wav",y.audio,int(out));
 }
 std::ofstream notes(dir+"/README.txt");notes<<"Offline only. Float32 WAV outputs may contain >1. No RT file writes. CPU excludes prepare/table generation/converter construction; includes conversion buffer loops. Cold/warm effects are not controlled. Legacy uses the 0.0.15 interpolation kernel at fixed nominal ratio; buffer-fill controller disabled to compare SRC kernels.\nSinc uses centered offline lookahead; leading field denotes required input lookahead, not inserted leading zeros. Apple uses Mastering / Max / PrimeNormal, with actual PrimeInfo logged. First-block input counts are computed availability bounds for custom/legacy and observed input-callback pulls for Apple. Impulse peak alignment is integer-sample; remaining fractional delay/filter differences are included in max/RMS. Aligned WAVs are steady-state crops. Response uses sinusoidal least squares after startup. Ripple covers measured tones <=90% lower Nyquist, not continuous guaranteed extrema. Alias/image values are measured spectral components, not a blanket stopband guarantee. Apple ASRC is N/A; analytic variable-phase reference used for ASRC.\n";
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
