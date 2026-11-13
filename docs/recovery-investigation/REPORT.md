# 0.0.21 — Underrun / Recovery investigation (observation-only)

Baseline: 0.0.20 / 362b84fc95519c42189d9d83c310923b635bac8e.

## Observed failure pattern

An observed 48 kHz / 512-frame hardware run contained occasional input-lookahead shortages without output-ring overruns. Callback processing time alone did not establish whether scheduling gaps or queue-control transients initiated the events. Aggregate counters do not reconstruct the affected waveform or identify a device-specific cause.

This report describes observation-only changes in 0.0.21. In 0.0.29, backlog repositioning was changed to use the new queue fill, and re-priming clears stale PI/filter/slew history. The historical reproduction below remains useful, but its unchanged-controller statements apply to the investigation version.

## What the counters actually mean

- ASRC Underrun: `ClockRateAdapter::next()` found fewer input frames than the FIR lookahead plus its safety guard, stopped consuming, and requested re-priming. This is NOT a Core Audio hardware XRun notification.
- Recovery counts the same starvation transition, as well as excessive-backlog repositioning. Five underruns with five recoveries and zero overruns is consistent with five starvation transitions, not ten independent failures.
- After the first unavailable sample the engine supplies zero source input to the existing AU/DSP chain until re-primed. AU tails can still produce output. The old counters do not record the number of zero-filled samples, so the old five events cannot be reconstructed from aggregate counters.
- The original minimum fill includes startup zero. It cannot identify the minimum during normal playback. A separate active minimum is now displayed.
- At 48k/512, the callback period is 10.667ms. Max processing time below that period does not exclude late wake-up, late Capture delivery, or a planned output pause. Existing timing starts on callback entry, not at the hardware deadline.

## Reproduced candidates

### 1. Queue transient + PI / ratio slew interaction (strong candidate)

The rate controller responds to queue occupancy as well as timestamp-derived clock differences. `+125ppm` is therefore not a direct measurement of oscillator drift.

The unchanged controller was simulated with actual clock difference +1.2ppm. With no queue disturbance it remains stable. A single +512, +1024 or +1520 frame backlog, such as Capture continuing while Output is paused/delayed, causes a large correction excursion. The 10ppm/s rate-of-change limit can keep consumption above the true incoming rate even after the controller's desired correction has reversed sign. Available input then falls toward the lookahead boundary.

For a +1520-frame step at about 30s, the idealized model reaches 511.81 frames at 158.56s with actual correction still +415.49ppm, even though P and I already request a negative correction. See reproduction.txt. This is a controller-only model: it deliberately does not enact the real engine's re-priming, and real `next()` can fail earlier because it needs enough lookahead at the end of an output block. These times/counts are NOT predictions of the observed events.

This candidate is consistent with the observed large fill range, correction far above the timestamp-derived drift, and positive consumption correction while current fill is already below target. It is not proof of what caused the actual past events. Output pause/resume from rack/preset operations, thread scheduling, or Capture packet batching could initiate the queue transient. The new records include time since planned Output resume, P/I/desired/feed-forward terms and filtered fill to distinguish these cases.

No controller gain, slew limit, integrator logic, target fill or re-priming policy was changed in this investigation.

### 2. Frozen write snapshot during the output block

AudioBridge acquires the producer write position once at block entry. `next()` uses that fixed limit for the whole block. If Capture publishes a new block while processing is underway, that new data is invisible to the current consumption guard.

A deterministic fixture reproduces a shortage with frozen available=514 and required=515 while live published input already makes 1026 frames available. This proves the behavior can occur; it does NOT prove it occurred in the observed run. Diagnostics capture frozen and live availability at the exact shortage.

The write-refresh policy was deliberately left unchanged. If real records show liveAvailable >= required at shortages, a bounded availability-refresh fix can be considered separately without changing FIR coefficients.

### 3. Actual Capture gap / scheduling / sample-time discontinuity

Still possible. An uninterrupted sample-time sequence with a large arrival gap differs from missing/restarted sample-time frames. Both are now observed. Output callback entry gaps are also measured, including planned pauses; long-gap candidates are not mislabeled as OS deadline misses.

## Added diagnostics

No audio sample data is logged and no WAV files are generated.

- Capture/Output callback entry intervals, cumulative long-gap candidates, timestamp continuity counters.
- Active minimum entry fill (startup excluded).
- Last active controller filtered fill, P, I, desired and feed-forward correction, without changing the calculations used for sound.
- Fixed SPSC queue from render to main thread; 128 event slots, no waiting or allocation, discarded-observation counter if full.
- Last 64 formatted events retained on the main thread, drained even when the panel is hidden.
- Per event: reason, host time, block/frame index, frozen/live write positions, cursor/phase, required input, entry fill, ratio, controller terms, Capture age/gap, Output gap, current bridge render duration, previous whole callback duration, cumulative timestamp jumps, and time since planned Output resume.
- Zero source-input frame counts before AU, separated into initial priming and post-recovery. These are not assertions of DAC silence.
- INPUT_LOOKAHEAD_SHORTAGE, EXCESS_BACKLOG and REPRIMED are separate event types. A re-primed observation does not increment the existing Recovery counter.

The existing Diagnostics panel shows the added observations after the original summary. After a new event, record a redacted diagnostic snapshot while the session is running. History is cleared on the next Start. No file output/formatting, allocation or mutex is added to audio callbacks. Controller fields while unprimed are the last active update, not a new control decision.

## Preservation / verification

- SincResampler.hpp, DSP.hpp, SpatialDSP.hpp and all AU Host files remain byte-identical to 0.0.20.
- Actual controller/ratio/availability/re-priming expressions are unchanged. Only observational fields/getters/stores were added.
- A separately compiled 0.0.20 engine and this build produce byte-identical audio over Legacy/Direct/Fixed/Async, including queue burst, Capture pause/starvation and gain/EQ/Spatial/mute automation: 4,505,600 Float32 samples.
- New diagnostic fixtures cover starvation/re-prime event sequence, zero-input accounting, arrival vs sample-time distinction and bounded queue overflow.
- No retrospective root-cause claim is possible: 0.0.20 did not retain the necessary event history. Next real-device events are needed to decide between these candidates.

## Reproduce without large audio files

```sh
bash scripts/test-recovery-diagnostics.sh
bash scripts/test-recovery-parity.sh
```

The parity script removes its temporary raw comparison samples on exit; it does not create WAVs. Source/diagnostic fixtures and textual results are small. The coefficient-quality comparison harness is not run by these tests.

## Candidate remediation, deliberately not implemented

If the queue-transient candidate is confirmed, separate oscillator drift estimation from deliberate pause/burst transients, evaluate rate-limit-aware anti-windup and recovery-state handling. Review any proposed change and re-run waveform/ratio tests before adoption. Do not widen the filter band, reduce tap count or change the DSP to mask buffer starvation.

If frozen snapshot is confirmed, evaluate one bounded fresh producer position read at the shortage boundary with the existing acquire/release memory ordering. If Capture gaps or hardware sample-time jumps dominate, investigate device/OS scheduling rather than retuning SRC blindly.

Apple IOProc timestamp semantics: https://developer.apple.com/documentation/coreaudio/audiodeviceioproc . The host callback entry, input acquisition time and output presentation time are distinct.
