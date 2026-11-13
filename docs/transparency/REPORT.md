# Bypass transparency: scope and measurements

Target implementation: 0.0.29. This investigation added an offline harness and numerical results; it did not change production audio processing. Investigation is paused. No end-to-end transparency or subjective improvement claim is made.

## Mode selection

The System Audio path constructs ClockEvidence with synchronized=false. Equal nominal rates do not establish synchronization. It normally selects Async Sinc even at 44.1/44.1 kHz; explicit Legacy selection or preparation fallback are exceptions. Direct tests exercise a proven-clock fixture, not the complete production capture-to-device path.

A 44.1 kHz diagnostic observation confirmed Async operation with approximately +5 ppm correction and no underruns, overruns or recoveries. That establishes interpolation/rate correction in the observed path; it does not establish the cause of a perceived difference from conventional playback. Nominal-rate matching removes 44.1-to-48 conversion, not all rate adaptation.

## Signal path

```text
Playback application / system output
→ device-specific Process Tap → private Aggregate Device
→ Float32 stereo extraction → Float32 ring → Clock/Rate Adapter
→ Input Gain → host-bypassed or active plugins → Crossfeed
→ 15-band GEQ → Master Gain → Limiter → Mute/Fade
→ Float32 planar stereo AUHAL client → driver/device output
```

Capture uses device stream 0 without stereo mixdown, excludes the host process and mutes the tapped direct hardware playback. Interleaved input selects the first stereo pair by stride; planar input selects the first two mono buffers. Copies do not intentionally apply gain. Aggregate drift compensation is requested; this alone does not prove a second resampler is active.

Production code does not generate dither or quantize to integer PCM. Finite samples above 0 dBFS are retained before the explicit limiter. Device virtual/physical format conversion and system gain at the tap boundary require separate measurement.

## Meaning of bypass

- Plugin host bypass skips the processor render, not the surrounding audio engine.
- GEQ Flat is mathematically unity but still executes the filter chain. GEQ Bypass is a separate control.
- Spatial OFF, unity gains and bypass transitions must settle before comparison.
- The sample-peak limiter is enabled by default, with a ceiling of -1 dBFS. A transparent comparison requires explicit limiter bypass or evidence that it never acts.
- Startup/resume fade, recoveries and clock drift prevent naive sample-by-sample subtraction.

## Offline results

Run `bash scripts/audit-transparency.sh`. The harness uses unchanged production engine headers, synthesized signals quantized to 16-bit levels, 44.1 kHz and 256-frame blocks. It excludes the first 51200 frames and measures 153600 samples per condition. No hardware capture or third-party processor is involved. See [internal-results.csv](internal-results.csv).

| Condition | Maximum numerical error | RMS error | Interpretation |
|---|---:|---:|---|
| Direct, EQ/limiter bypassed | 0 | 0 | Three zero-sign bit mismatches; not universal bit identity |
| Direct, EQ Flat, limiter bypassed | 4.8649e-13 | 1.5065e-15 | Seven bit mismatches near zero; no basis for an audible-effect claim |
| Async, EQ Flat, limiter bypassed | 0.60817 | 0.23109 | Unaligned residual dominated by accumulated timing offset; **not a distortion metric** |
| Direct, EQ Flat, active limiter; separate hot sine | 0.0987393 | 0.0691748 | Input peak 0.989990, output peak 0.891251; explicit dynamics processing |

The synthetic Async queue schedule ends near +46.44 ppm. This is a test condition, not an estimate of a physical device's drift. Peaks remain approximately 0.6 in that test. A large unaligned residual does not demonstrate poor conversion quality.

## Unresolved differences and measurement plan

Conventional playback and the capture/host path differ in scheduling, aggregate handling, host rate adaptation, DSP and output-client configuration. Playback-application processing, system mixer gain, tap position relative to gain, actual drift compensation, virtual/physical device ASBD, channel routing and hardware mixer state are not established by the offline test.

Diagnostic priority:

1. Verify limiter state and actual gain reduction against the source peak.
2. Measure both paths' level and channel mapping before interpreting timbre. Keep playback-application volume and device routing fixed; report the original gain difference before normalization.
3. Record the actual adapter mode/ratio and time drift. Do not force Direct on unproven clocks merely to obtain a null.
4. Isolate capture, aggregate and output boundaries using timestamps and stream-format metadata.

If supported, capture the same digital output/loopback on a common recorder clock. Otherwise use identical analog routing, recognizing DAC/ADC noise and nonlinearity. An unmuted process tap by itself is not a measurement of the final hardware output.

For two recordings: estimate integer lag, L/R gain and polarity, then examine lag over successive windows. Report peak/RMS and spectra both before and after level matching. If delay drifts, fixed alignment is insufficient: report the ppm slope and a separately time-aligned residual, including the interpolation method. A resampled null does not establish bit identity of the originals. Direct/direct repeats establish the measurement floor.

An end-to-end null test has not been performed. Future stage capture would require bounded preallocated transfer to an off-thread writer, with timestamps and drop counters; no callback file IO or allocation. No such capture feature was added here.

References: [Core Audio tap description](https://developer.apple.com/documentation/coreaudio/catapdescription), [tap mute behavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior). These describe API semantics, not end-to-end transparency guarantees.
