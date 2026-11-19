# HRTF virtual speakers

The Spatial panel offers OFF, Crossfeed and HRTF. HRTF is for headphone listening. Drag either virtual speaker or scroll over it to set the linked horizontal angle from ±10° to ±75°. Reset Field returns to ±60°. The HRTF renderer uses a fixed source distance. Distance and Amount controls are available in Crossfeed.

The Apple Spatial Mixer uses HRTF HQ with two mono point-source inputs and a Float32 planar stereo output at the device rate. The source distance is fixed at 1.5 m. The renderer requests interaural delay and disables internal reverb. Its output goes to Master GEQ, Master Gain and the existing limiter. Angle changes are rate-limited, and HRTF uses a short wet/dry ramp. Switching between Crossfeed and HRTF passes through dry audio so the two transformations do not stack. Head tracking and personalized HRTF are outside this implementation.

The mixer is prepared before output starts. The host uses fixed scratch buffers and calls the native mixer in slices of up to 512 frames. It performs no host allocation or disk IO in the render loop. The mixer is system code and its internal resource behavior is not asserted. Initialization or render failures are reported in the Spatial panel and the affected audio uses the dry path. A Stop/Start re-prepares the mixer.

Rack settings store the selected mode and separate Crossfeed/HRTF angles. Existing files without the HRTF flag retain their OFF or Crossfeed behavior.

## Validation

Run `bash scripts/test-hrtf.sh` from the repository root in a macOS session with Audio Unit services available. The test checks directional impulse responses, audible-path angle changes by numerical comparison, and exact dry output after the fade completes. Supported rates in the test are 44.1, 48, 96 and 192 kHz. In a local mixer-only run at 48 kHz, the left virtual speaker's near/far impulse peaks were 5/17 samples and a 512-frame call averaged about 7 µs. These are impulse peak locations and offline render timings, not end-to-end latency or callback deadline measurements.

No gain compensation is added. HRTF changes the frequency response and may also change perceived loudness. Headphone listening, level matching with music and sustained playback under real device load remain separate validation steps.

[Apple Spatial Mixer](https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_spatialmixer)
