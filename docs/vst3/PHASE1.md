# VST3 first milestone — 0.0.22

Update 0.0.25: declared auxiliary audio buses are now retained in negotiation and explicitly disabled. Fixed metadata covers at most 8 buses per direction and 64 channels per bus; main bus 0 must remain stereo and additional buses must be auxiliary. AudioBusBuffers includes all buses with matching channel pointer arrays; inactive sample pointers are null as allowed by the SDK. No external sidechain routing is provided. Neutron 3 Elements (2 stereo input buses / 1 stereo output) reproduced the previous rejection and passes audio/GUI checks after the fix. Error stages now identify bus negotiation accurately.

## Usage

1. Build with `bash scripts/build.sh`. For a fresh checkout first run `bash scripts/setup-vst3.sh` (network needed once).
2. Click **Scan VST3**. This is asynchronous; the status line reports discovery results.
3. Click **Add an effect → VST3 → effect name** in an empty slot.
4. **Editor ↗** opens the manufacturer's NSView in a floating panel. Input Gain remains adjustable in the main window.
5. Bypass, reorder, remove and existing rack Save/Load work with both backends. VST3 presets are selected **inside the manufacturer's editor** in this milestone; BOX's AU preset browser is disabled for VST3.

The common `RackEffect` interface extracts rack ownership/dispatch from the AU implementation. The AU implementation bodies, ClockRateAdapter/SincResampler, DSP, GEQ, Spatial and Limiter algorithms are unchanged by the VST3 work. The earlier 0.0.21 recovery observation changes remain in the working tree.

## Supported contract

- macOS arm64, **Float32 stereo planar**; device output rate; at most 4096 frames per process call (rack splits larger blocks).
- One main stereo audio input and output at index 0. Declared auxiliary buses are retained in negotiation and explicitly disabled (up to 8 buses per direction / 64 channels per bus). Event buses are disabled. External sidechain routing, additional main buses, Instrument/MIDI and Float64-only processors are not supported.
- Separate component/controller and combined implementations; separate components are connected using SDK IConnectionPoint proxies that reject off-main-thread message delivery.
- Legacy setProcessing no-op responses (`kNotImplemented` / `kResultFalse`) are tolerated as in the SDK audiohost sample; successful setupProcessing/setActive are mandatory and render errors still latch dry/error.
- Native NSView GUI, screen-bounded viewport with scrolling for oversized editors, plug-in initiated sizing, floating panel close/reopen. User-driven resizable-editor integration, advanced keyboard/host extensions and automation timeline are not implemented.
- kParamValuesChanged transfers controller values; latency changes update the reported latency. IO/reload restart requests put the slot into dry/error mode and require re-prepare (Stop/Start or remove/reinsert); no live bus rebuild on the audio thread.
- In-process processing/editor. **Only scanning is crash-isolated**; a crashing manufacturer processor/editor can still crash BOX. Rosetta bridge and out-of-process DSP are outside this milestone.

Discovery is a candidate list, not a compatibility certification. Stereo negotiation/initialization occurs on insertion and a failed insertion preserves the current rack.

## Lifetime / realtime boundaries

- SDK pinned to v3.8.0_build_66, root commit `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`; only base, pluginterfaces and public.sdk submodules. MIT notice copied into the application Resources for shell and CMake builds.
- Probe helper is the same executable with `--vst3-probe <bundle>`; it only asks the factory for class metadata. Each bundle gets an 8-second deadline; a timed-out helper is killed and reaped. No probing/formatting/file IO occurs in process().
- Modules are shared across live instances. Component/controller/view teardown precedes module exit. Factory host context outlives instances.
- Component creation, prepare, state serialization and GUI work are outside audio callbacks. Mutating an existing rack still uses the existing output pause/resume boundary; capture continues.
- DSP uses preallocated input/output arrays, bounded parameter queues and atomic SPSC transfer. Per-block edits are coalesced to the last value per ID at offset zero (no sample-accurate timeline automation).
- Limits: 2047 pending GUI edits, 512 distinct input/output parameter IDs per block. Input overflow explicitly marks the slot as error/dry. Excess processor-to-GUI meter updates may be dropped; audio is unaffected. Large preset/program changes may need more capacity in a later compatibility pass.
- Host message allocation requests from within process() are rejected. Manufacturer code may still allocate/block internally; the host cannot guarantee third-party realtime behavior.
- Render failure/nonfinite output preserves the dry input and latches an error. There is no implicit [-1,+1] clamp; silence flags are honored independently for L/R.

## State compatibility

AU-only files remain schema version 1. Files containing VST3 use version 2, with path/class ID and separate component/controller byte streams inside each VST3 state dictionary. The loader accepts versions 1 and 2, prepares/restores a replacement rack before swapping, and preserves the current rack on failure. Moved/missing VST3 bundles are not automatically relocated. State methods require output to be paused. Whole-BOX gain/GEQ/Spatial persistence remains a separate task.

## Validation on 2026-11-13

- Test-only `BOXGain.vst3`, created under ignored `build/`, never installed globally: unity bit exact, +12 dBFS samples preserved, GUI edit halves the signal, bypass bit exact, component/controller state roundtrip, 44.1/48/96 kHz prepare, eight editor close/reopen/teardown cycles.
- AddressSanitizer/UndefinedBehaviorSanitizer fixture run passes, including GUI lifecycle/state roundtrips.
- 8 × 1000 process calls at 512 frames: no observed C++ `new/new[]` allocations in the fixture callback. This is not a malloc/mutex proof for third-party code.
- Unsanitized fixture timing (96 kHz / 512 frames / 1000 calls): mean 1.144 µs, max 2.834 µs, p95 1.208 µs, p99 1.250 µs, p99.9 1.292 µs. This measures the simple fixture/host process call, **not** the full engine or manufacturer DSP; it is a smoke benchmark, not a performance guarantee.
- AU/VST3 mixed rack: 8192-frame splitting, channel separation/headroom, editor routing, reorder/remove, failed insertion retaining the rack.
- Manufacturer smoke test: installed arm64 NeuralAmpModeler and Ozone 9 Elements initialize, process 100 blocks of a same-polarity L/R 440 Hz sine with nonzero finite output and open/close their NSViews. This test does not certify all parameter/preset combinations or long-duration device playback.
- Installed-bundle helper scan: **12 Effect candidates, 17 skipped bundles**; one Instrument bundle filtered. Installed McDSP VST3 executables are x86_64-only, so this arm64 host cannot use those copies. Their working AU versions remain available.
- Existing Apple AU render/state/bypass/rate tests, AU menu/8-slot tests and AU preset identity/dirty-marker/zapping regression tests pass with native macOS services.
- Existing bridge/DSP tests and rate-adapter tests pass. Four-mode parity with shipped 0.0.20 remains byte identical across 4,505,600 Float32 samples. No SRC WAVs generated.

Run `bash scripts/test-vst3.sh`, then `bash scripts/test-vst3-ui.sh`. Native AU and Metal-backed manufacturer editors need normal access to macOS audio/graphics services; a restricted test process may fail despite the installed application working. `./build/vst3_tests --scan` exercises helper isolation; `./build/vst3_tests /Library/Audio/Plug-Ins/VST3/NeuralAmpModeler.vst3` exercises that installed plug-in.

## Follow-up

Long-duration AudioFuse playback and manufacturer-specific compatibility testing; expand bus/restart handling where measured necessary; VST3 program/preset browser; broader parameter queue stress; optional process isolation. HRTF is a later task. No SRC coefficients or existing DSP algorithms changed for this milestone.
