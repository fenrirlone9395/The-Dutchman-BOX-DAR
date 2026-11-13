> Current status: Auto Clock/Rate Adapter is the default from 0.0.19; an unproven clock relationship selects ASRC. Legacy remains a manual fallback. This report describes the 0.0.16 candidate and its measurements; historical default and recovery behavior must not be interpreted as current specifications. Recovery state handling changed in 0.0.29.


# Audio Engine Phase 1 candidate — 0.0.16

Baseline: 0.0.15 / b6b4c4135c42f078591332845322c61d38219adc.

## Decision

**Implementation and offline comparison harness are present, but the custom sinc is NOT promoted to the production default.** Legacy remains selected by default. The app menu's “Legacy Linear” checkbox can be unchecked to opt into the new clock adapter on the next Start. No automatic mid-stream fallback/mode switching occurs.

The custom high-quality profile meets the sampled passband/alias objectives but is approximately 5.3–5.6 times slower than Apple Mastering/Max in the offline kernel comparison. Apple has lower measured residual alias/image components too. A non-realtime callback benchmark also observed a Fixed SRC wall-time outlier exceeding the callback period. These are explicit reasons to withhold default promotion, rather than claiming the custom implementation is the best choice.

Recommended next production backend: Apple AudioConverter for proven fixed-ratio conversion, after streaming/priming and warm-up allocation tests. For asynchronous conversion, evaluate a mature streaming variable-ratio library (e.g. libsamplerate full API) against this same harness before selecting a default. Neither alternative has been added to the production callback in this change. Do not change AudioConverter sample-rate properties inside the callback to emulate ASRC.

## Scope and implementation

- Float32 Capture, Float32 ring (32768 stereo frames), Float32 AU buses and existing post-adapter chain remain.
- No modifications to AU Host, DSP.hpp/GEQ/Limiter, or SpatialDSP.hpp/Crossfeed.
- Direct copies samples without interpolation. Fixed and Async share the sinc kernel. Legacy uses the exact original interpolation and fill correction math.
- Sinc uses 2048 fractional phases with coefficient-table interpolation, Kaiser beta=12, 1024 * max(1, Fin/Fout) taps rounded up to 32, normalized DC coefficients, and a 99% lower-Nyquist cutoff with a +1000ppm anti-alias guard. Float32 buffers/coefficient storage, double local sums; no whole-engine Float64 migration.
- Larger-than-budget rate pairs fail preparation and select Legacy before capture/output start, with a visible reason. Tables over 8192 taps are rejected; normal requested pairs use 1024/1120/1024/2048 taps.
- Table construction precedes capture IO. Output AUHAL initialization and output start are separated so no callback runs while the adapter is prepared. AU initialization/format policy is unchanged.
- Fixed history retained in the ring, lookahead availability checked per sample. Recovery is counted and reprimes; normal +/-100ppm drift does not drop/duplicate samples.

## Clock selection and telemetry

Synchronized + equal rate => Direct. Synchronized + unequal rate => Fixed. Independent or unknown => Async, including unequal nominal rates. An explicit Legacy selection overrides this. Unknown does not enter Direct.

The current tap-only Aggregate has no verified clock chain to the output endpoint and requests tap drift compensation. **This version deliberately treats the live Process Tap path as unproven/Async when opted in.** ScreenCaptureKit clock identity is also unknown/Async. Direct/Fixed have synthetic proven-clock fixtures and are not forced onto live hardware based solely on matching 48k labels or physical device UID. A general hardware synchronization verifier remains future work; no aggregate reconfiguration was slipped into Phase 1.

Control-thread snapshots collect UID/device, nominal/actual rate, clock domain/source/device, aggregate composition and requested drift-compensation state. Unsupported values are Unknown. Capture IO's input timestamp and AUHAL output timestamp are passed via fixed atomic mailboxes. Sample/host slopes use >=10s windows, with reset on discontinuity and smoothing. Timestamp estimates are distinct from reported actual rates. Device/rate/domain/source changes stop and require Start again. Aggregate configuration is locally owned and unchanged.

Controller: queue error filtered with a 2s time constant, PI proportional 50ppm/ms and integral 2ppm/ms/s, bounded integral and total correction +/-1000ppm, maximum slew 10ppm/s. Timestamp ratio is feed-forward when valid. Ratio is continuously ramped across each output block; phase remains continuous. Ring fill is measured at callback entry; raw retained history and effective unread fill are distinguished in diagnostics.

App menu: **Audio Engine Diagnostics…** (Cmd-Option-D). Shows rates, mode/reason, actual and timestamp estimates, ratio, ppm, current/target/min/max fill, kernel latency, lookahead, under/overrun/recovery counts, and callback mean/max/approximate percentile upper bounds. Diagnostics are formatted on the main thread only. The live histogram is approximate; offline sorted timing results below are exact for that run.

## Measured fixed-ratio quality

macOS 14.8.9, Apple Silicon, clang Release -O3. Measured on this machine; not a cross-machine guarantee. Same synthesized Float32 stereo input for all methods. Apple: Mastering / Max / PrimeNormal. Legacy kernel comparison uses fixed nominal ratio, without its ring-fill servo, to isolate interpolation quality. The separate parity and callback tests use the actual legacy engine.

| In -> Out | Custom sampled passband ripple, dB | Worst sampled alias/image, custom / Apple dB | Custom / Apple us per output stereo frame |
|---|---:|---:|---:|
| 44.1 -> 48k | 0.000002377 | -132.47 / -171.45 | 1.294 / 0.238 |
| 48 -> 44.1k | 0.000001536 | -122.54 / -177.59 | 1.399 / 0.263 |
| 88.2 -> 96k | 0.000002303 | -132.23 / -169.87 | 1.291 / 0.235 |
| 96 -> 48k | 0.000000790 | -123.23 / -147.64 | 2.590 / 0.459 |

Ripple covers sampled tones up to 90% of the lower Nyquist, not a continuous extremum guarantee. Alias/image numbers are relative to source tone amplitude, at the frequencies recorded in frequency.csv. They are NOT a guarantee of whole-band noise floor or all-signal stopband attenuation. Very small Apple component estimates do not imply equivalent effective PCM bit depth.

Legacy: measured ripple about 6.23dB (44.1->48), 5.19dB (48->44.1), and alias around 0dB on the 96->48 downsample probes. Flat response for the integer-ratio legacy decimator does not mean anti-aliasing is present.

Near Nyquist: custom passes 98% of lower Nyquist within about a few millionths dB on the sampled fixed-ratio tones. At 99%, transition attenuation is about -6.09dB for 44.1->48 and -9.90dB for 48->44.1, versus Apple's approximately -6.09dB. This includes the custom ASRC guard band; it is not hidden as “flat to Nyquist”. Full frequency values are in the CSV.

Multitone vs Apple after impulse-peak alignment and steady-state crop: custom max error 1.49e-8..2.98e-8, RMS 3.40e-9..5.90e-9. Anti-phase L/R sum error was exactly 0 for every method. The multitone contains 100/1000/5000/10000/18000Hz; these error values must not be generalized to near-Nyquist signals.

## Latency / priming

Custom lookahead: 512/560/512/1024 input frames for the four rate pairs, approximately 11.61 / 11.67 / 5.80 / 10.67ms. This is larger than the original short-kernel estimate because the measured quality profile was increased from 256 to 1024 base taps. The live target buffer remains at least 2048 frames and grows for lookahead/ratio needs. Do not add lookahead and queue blindly: future input is read from already buffered frames, so overlap exists; actual end-to-end latency needs timestamp/loopback measurement.

Offline output has centered lookahead and no artificial leading delay; all three impulse peaks aligned at offset 0 in these fixtures. Sinc lookahead, Apple-reported PrimeInfo, and **first-block input availability/pull counts** are separately recorded. The custom/legacy first-block counts are conservative computed availability bounds; the Apple count is observed in its input callback. Apple reported zero PrimeInfo leading/trailing here, but pulled 812/911/812/1664 input frames before its first output block. Zero PrimeInfo is not interpreted as zero buffering/latency. Samples before startup and final filter tail are excluded from steady-state error measurements. Integer peak alignment is recorded; residual fractional phase/filter differences remain part of measured error, not silently corrected away.

## ASRC quality and drift

Waveform test: +/-100ppm sinusoidal ratio modulation with a 70s period (maximum slew 8.98ppm/s), 72.2s signal, full positive and negative cycle. Analytic sine reference uses the identical continuous source position. Apple fixed AudioConverter is marked N/A for this variable-ratio test; it is not reconstructed per block.

At 44.1->48k, 21,610Hz (98% lower Nyquist): custom max error 2.00e-7, RMS 7.22e-8. At 48->44.1k the same tone: max 9.09e-8, RMS 2.53e-8. Legacy max errors were about 0.242 and 0.211 respectively. Full results for 10%, 90%, 98% lower Nyquist are in asrc-spectrum.csv. Hann-window FFT of residuals is included. These residual spectral components include Float32 input quantization/filter error and are not a subjective audibility claim or an independent-clock hardware test.

Controller-only simulation: each +/-10/50/100ppm runs one simulated hour, both without feed-forward and with timestamp feed-forward becoming available after 10 seconds. Fill stayed within approximately 1988.3..2107.7 around target 2048, and final correction converged within 0.1ppm (printed results are closer). This uses the controller without running billions of FIR operations; it is explicitly not an hour-long full audio-path test.

Full Float32 ring + actual ASRC/DSP tests: each +/-10/50/100ppm with burst-arrival jitter, 8 simulated seconds, zero under/overruns and no DC discontinuity after settling. More long-duration hardware and varying-block tests are required before production promotion.

## Callback cost and RT safety

10,000 measured blocks after warm-up, 256 frames / 48k output. Empty AU rack, existing DSPs bypassed. Wall time measured on an ordinary offline thread, including OS scheduling/preemption. The system was not isolated from other desktop/offline test activity. These are **not** real-device callback deadline guarantees.

| Path | mean us | max us | p95 us | p99 us | p99.9 us |
|---|---:|---:|---:|---:|---:|
| Original 0.0.15 | 19.54 | 61.29 | 20.58 | 23.58 | 35.50 |
| New Legacy | 22.49 | 61.33 | 35.75 | 58.13 | 58.58 |
| Direct | 18.85 | 48.50 | 19.42 | 20.67 | 36.79 |
| Fixed Sinc 44.1->48 | 356.86 | **16,740.25** | 368.13 | 464.46 | 3,514.25 |
| Async Sinc 48->48 | 342.78 | 785.63 | 358.42 | 369.13 | 398.00 |

The 16.74ms wall-time outlier exceeds the 5.33ms nominal block period. Scheduling may be responsible for part of it, but it is retained rather than discarded. Offline under/overrun counters were zero because this harness is not a real-time producer deadline test. Further real-device measurement and host-load testing is mandatory. AU load was not part of this benchmark.

Audio callback uses precomputed tables/fixed ring/history and atomic telemetry, no formatting, file IO, mutex, AU/Converter creation or explicit heap operations. Test-time C++ new/new[] guards assert no allocation during the exercised full render path. ASan/UBSan tests pass. This guard is not comprehensive instrumentation of malloc inside arbitrary third-party AUs or OS services. Apple AudioConverter exists only in the offline harness.

## Regression / rollout / open work

- Legacy byte parity vs separately compiled baseline: 1,536,000 Float32 samples across rates and gain/EQ/Spatial/Limiter/mute automation.
- Direct full-engine null after fade AND bypass smoothing settle: 44.1/48/96k bit exact, max=0, RMS=0; test samples include >0dBFS values. The finite generated sequence does not include every IEEE special value. An adapter-only fixture separately verifies copying of signed zero, subnormals and Float32 max. The full existing DSP bypass path may canonicalize signed zero; no universal IEEE bit-pattern claim is made for the entire engine and the protected DSP code was not changed.
- Existing buffer, SRC drift, DSP, Spatial and multi-channel capture-buffer tests pass.
- Native main-window/rack/EQ/Spatial/Diagnostics UI tested without starting audio capture.
- End-to-end hardware loopback and hardware-clock qualification are **not established by these offline tests**. No source/device routing was changed for measurements.
- The comparison baseline is retained. Rollback via Legacy checkbox on the next Start, or the unchanged 0.0.15 app. No automatic streaming fallback.
- Future production proposal: fixed Apple backend plus independently benchmarked mature ASRC, retain this custom sinc as a transparent comparison fixture until it earns promotion. libsamplerate's full streaming API supports ratio transitions: https://libsndfile.github.io/libsamplerate/api_full.html . No external dependency was introduced here.

## Reproduce

```sh
bash scripts/test-legacy-parity.sh
bash scripts/test-rate-adapter.sh
bash scripts/test.sh
bash scripts/test-spatial.sh
bash scripts/test-tap-input.sh
bash scripts/test-main-ui.sh # macOS login GUI session, does not start capture
bash scripts/compare-src.sh build/src-comparison-release
bash scripts/analyze-asrc.sh build/src-comparison-release
bash scripts/benchmark-rate-adapter.sh 10000
# For more tail samples, use 100000 instead of 10000.
```

WAV writing and all converter construction are confined to offline tests. WAVs/CSV files are generated under ignored build/; small measurement CSV snapshots accompany this report. Do not play >0dBFS test signals at unsafe output levels. No unit test silently applies normalization to hide gain differences.
