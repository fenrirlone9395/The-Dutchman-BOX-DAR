// Offline spectral analysis only. The variable-phase analytic reference includes
// the deliberately commanded +/-100ppm motion; residuals quantify extra components.
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <numbers>
#include <vector>
using Complex=std::complex<double>;
static void fft(std::vector<Complex>& x){size_t n=x.size();for(size_t i=1,j=0;i<n;++i){size_t bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(x[i],x[j]);}for(size_t len=2;len<=n;len<<=1){Complex rotation=std::polar(1.,-2*std::numbers::pi/len);for(size_t i=0;i<n;i+=len){Complex w=1;for(size_t j=0;j<len/2;++j){Complex a=x[i+j],b=x[i+j+len/2]*w;x[i+j]=a+b;x[i+j+len/2]=a-b;w*=rotation;}}}}
int main(int argc,char**argv){if(argc!=2)return 2;std::string dir=argv[1];std::ofstream report(dir+"/asrc-spectrum.csv");report<<"input_rate,output_rate,method,tone_hz,max_error,rms_error,largest_residual_component_dbfs,residual_component_hz\n";
for(auto pair:{std::array<double,2>{44100,48000},{48000,44100}})for(double frac:{.1,.9,.98})for(bool legacy:{false,true}){
 double in=pair[0],out=pair[1],hz=std::round(std::min(in,out)*.5*frac/2)*2;
 std::string path=dir+"/ASRC-"+(legacy?"Legacy-":"")+std::to_string(int(in))+"-"+std::to_string(int(hz))+".wav";std::ifstream file(path,std::ios::binary);if(!file){std::cerr<<path;return 1;}file.seekg(40);uint32_t bytes=0;file.read(reinterpret_cast<char*>(&bytes),4);std::vector<std::array<float,2>> audio(bytes/8);file.read(reinterpret_cast<char*>(audio.data()),bytes);if(!file)return 3;
 size_t start=size_t(.3*out),end=std::min(audio.size(),size_t(71.8*out)),length=end-start,n=1;while(n<length)n*=2;std::vector<Complex> error(n);uint64_t position=0;double phase=0,max=0,squared=0,windowSum=0;
 for(size_t i=0;i<end;++i){if(i>=start){double reference=.25*sin(2*std::numbers::pi*hz*(position+phase)/in),e=audio[i][0]-reference,w=.5-.5*cos(2*std::numbers::pi*(i-start)/(length-1));max=std::max(max,std::abs(e));squared+=e*e;error[i-start]=e*w;windowSum+=w;}phase+=in/out*(1+100*sin(2*std::numbers::pi*(i/out)/70)*1e-6);auto used=uint64_t(phase);position+=used;phase-=used;}
 fft(error);double peak=0;size_t index=0;for(size_t i=1;i<n/2;++i){double magnitude=std::abs(error[i])*2/windowSum;if(magnitude>peak){peak=magnitude;index=i;}}
 report<<in<<','<<out<<','<<(legacy?"LegacyLinear":"PolyphaseSinc")<<','<<hz<<','<<max<<','<<sqrt(squared/length)<<','<<20*log10(std::max(peak,1e-20))<<','<<index*out/n<<'\n';report.flush();
 std::cout<<in<<"->"<<out<<' '<<(legacy?"Legacy":"Sinc")<<' '<<hz<<"Hz: residual peak "<<20*log10(std::max(peak,1e-20))<<"dBFS\n";
}}
