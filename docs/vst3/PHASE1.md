# VST3 host: scope and validation

This document covers the VST3 implementation introduced in 0.0.22 and subsequent rack, persistence and catalog updates through 0.0.29. See the README for current operation.

## Supported contract

- Native arm64 Float32 planar stereo, at the output device rate; rack blocks are split at 4096 frames.
- Main audio bus 0 must negotiate stereo. Additional audio buses must be auxiliary and are explicitly disabled. Metadata is bounded to 8 buses per direction and 64 channels per bus. External sidechain routing is not provided.
- Separate or combined component/controller implementations. SDK connection proxies reject off-main-thread message delivery.
- NSView editors in floating panels, including plugin-initiated resize and a scrollable viewport for oversized editors.
- AU/VST3 coexist in eight fixed insert positions. Replacement preserves slot bypass; failure preserves the previous effect. Empty slots are skipped by processing.

Instrument/MIDI processing, Float64-only plugins, Intel bridging, user-driven editor resizing and complete live IO reconfiguration are not implemented. IO/reload requests latch dry/error behavior pending re-prepare. Legacy no-op setProcessing responses are tolerated, but successful setupProcessing/setActive remain mandatory; render errors still latch dry/error.

## Realtime and lifetime boundaries

The pinned SDK is v3.8.0_build_66, root commit `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`. SDK source is fetched by the setup script; its MIT notice is included in application resources.

Plugin construction, editor work, state serialization and catalog operations occur outside audio callbacks. Rack mutations use the output pause/resume boundary. Processing uses preallocated sample arrays, fixed parameter queues and atomic SPSC transport. Up to 2047 pending GUI edits and 512 distinct parameter IDs per block are supported; input overflow latches error/dry behavior. Excess processor-to-GUI updates may be dropped. Host message allocation requests during process() are rejected. Third-party processing can still allocate or block internally.

Scanning uses the executable's probe mode, with an 8-second per-bundle deadline. Timed-out helpers are killed and reaped. Startup reads the catalog cache before a background metadata comparison; only changed/new bundles are probed, removed entries disappear, and unchanged failed probes remain cached. Manual Scan performs a full rescan. Menu choices retain identity across catalog refreshes.

**Only scanning is isolated.** A crashing processor or editor can still terminate the host. Shared modules outlive their component/controller/view instances.

## Persistence

The current v4 rack format includes empty positions and optional built-in settings. The application binds the built-in DSP settings for Save/Load. Older v1–v3 files are accepted; absent built-in settings retain current values. Plugin state includes bundle path, class ID and component/controller streams. These installation paths are functional fields in local rack files, not suitable as public examples without redaction.

Moved or missing bundles are not automatically relocated. Replacement instances and settings are validated before the active rack is exchanged; failures leave it unchanged. Device selection, transport and Emergency Mute are not restored from rack files. VST3 preset selection remains inside the manufacturer's editor.

## Validation and limits of evidence

The deterministic test-only effect is built under ignored build output, not installed into system plugin folders. Tests cover sample identity at unity, over-0 dBFS headroom, native GUI parameter changes, bypass, state roundtrip, rate re-prepare, editor lifecycle, disabled auxiliary bus buffers, mixed-format rack operations, fixed empty positions and file compatibility. Catalog tests cover unchanged/new/modified/deleted bundles, negative caching, corrupt cache recovery and forced rescans.

Selected third-party effects have also been checked for initialization, known-signal output and editor creation. This is not a compatibility list or a guarantee for all presets and long-duration hardware playback. Architecture incompatibility is distinct from host format support.

```sh
bash scripts/setup-vst3.sh
bash scripts/test-vst3.sh
bash scripts/test-vst3-ui.sh
bash scripts/test-vst3-catalog.sh
```

Native audio/GUI tests require the relevant macOS services. Sanitizer coverage and timing scope are defined by each script. Fixture timing is not a full-engine performance guarantee. Future work includes broader manufacturer compatibility, live restart handling, preset browsing and optional processing isolation.
