# PulseBar

PulseBar is a local macOS menu-bar system monitor built in Swift + SwiftUI.
It is an original implementation inspired by iStat-style capabilities, with no copied UI or branding.

## MVP Status

Implemented in this repo:
- Menu bar summary v2 with compact / balanced / dense layouts plus per-metric text, icon, or sparkline rendering
- Overview-first popover with a card dashboard plus restored detailed CPU, Memory, Battery, Network, Temperature, Disk, and Settings sections
- Unified chart windows across compact tabs and detached panes: 15m / 1h / 6h / 1d / 1w / 1mo
- Persistent chart history across launches with shared chart-window rollups for metric, memory, and temperature history
- Generic metric history persistence: CPU, battery, network, disk, FPS, and other plot-backed samples persist for 30 days while preserving offline gaps between sessions
- Providers: CPU (Mach user/system/idle + per-core + load average + uptime), Battery (IOKit power sources), Memory (Mach VM stats + native macOS pressure level + swap usage + paging rates), Process CPU (`ps` top list with cache), Process memory (`ps` top list with cache), Network (`getifaddrs` aggregate + per-interface), Disk (free space + IOBlockStorageDriver read/write + SMART with combined fallback), FPS (ScreenCaptureKit compositor frame stream with display-refresh fallback when screen capture access is unavailable), GPU summary (private IOAccelerator/AGX performance statistics for processor + memory usage)
- Dashboard context enrichments: active network interface, SSID, VPN heuristics, private IP addresses, battery energy mode, significant-energy processes, sensor favorites, and sensor presets
- Temperature monitoring:
  - standard mode via `ProcessInfo.thermalState` (no privileges)
  - privileged mode via helper source chain: IOHID temperature sensors + AppleSMC fan probe + `powermetrics` fallback
  - Sensors overview card with favorites-first curation and a direct drill-down into the restored temperature detail surface with detached adjacent history pane (hover preview, click pinning, hide/reset sensor controls, shared chart windows, drag-to-zoom, double-click reset)
  - Temperature detail tab now keeps thermal-state history visible in standard mode and shows aggregate primary/maximum traces whenever those metric histories exist, even if privileged per-sensor channels are unavailable
- last-known privileged temperature snapshot persists across relaunches so quiet startup still shows sensors without triggering admin prompts
- Shared light-theme palette now applies across overview, detailed tabs, detached panes, chart controls, and settings so the popover no longer switches between polished and washed-out surfaces
- Dashboard cards reuse prepared rolling render models rather than rebuilding live Swift Charts for every refresh
- Startup latest-sample hydration uses a maintained latest-metric cache table instead of grouping the full metric history database on launch
- Profiles: Quiet / Balanced / Performance / Custom
- Power-source auto-switch rules (AC and Battery profile mapping)
- Settings persistence via `UserDefaults` + `settings.v4` migration model, including dashboard layout/order, menu bar display preferences, sensor favorites/presets, and per-surface chart-window memory
- Internal settings ownership now lives in `SettingsController`, while runtime presentation state and provider failures are published via `TelemetryStore`
- Global refresh frequency (`1s...10s`) that applies uniformly to the sampling engine, privileged temperature sampling, and subprocess-backed providers
- Launch-at-login toggle using `SMAppService`
- Multi-rule alerts (CPU, temperature, memory pressure, disk free-space thresholds) with in-app recent alert history plus system notifications when running as an app bundle
- Powermetrics provider with parser, retry backoff, and status reporting
- Privileged helper executable (`PulseBarPrivilegedHelper`) with local IPC contract
- Shared chart preparation pipeline with stable series keys, centralized sanitization, revision-driven chart refreshes, and detached-pane viewport zoom support
- Feature-scoped presentation stores and diagnostics counters for compact surfaces, process polling, detached panes, and batch-handler timing
- Provider failure observability surfaced in Settings instead of silently swallowing sampling errors

## Requirements

- macOS 13+
- Apple Silicon tested target (M1+)
- Swift 6 toolchain
- Full Xcode recommended for the app UX workflow
- Current developer machine reference: macOS 26.2 on M1 MacBook Pro

## Build and Run

### Option A: Swift Package (works with CLI toolchain)

```bash
swift build
swift run PulseBarApp
```

### Option B: Xcode

1. Install full Xcode.
2. Point developer tools to Xcode:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
3. Open the package/project in Xcode and run `PulseBarApp`.

## Launch at Login

PulseBar uses `SMAppService.mainApp`.
- In debug and unsigned contexts, registration may fail depending on launch location and signing.
- The Settings screen surfaces success/failure status text.

## Privileged Metrics (Optional Mode)
Privileged temperature sampling is enabled by default for local personal builds.
- App process remains unprivileged; privileged sampling runs through `PulseBarPrivilegedHelper`.
- Helper source chain: IOHID temperature services first, AppleSMC fan telemetry probe, then `/usr/bin/powermetrics` sampler fallback.
- Some macOS/tool versions expose only power or thermal-pressure data via `powermetrics`; when that happens, PulseBar still prefers IOHID Celsius sensors and degrades to standard thermal state only if privileged sources are unavailable.
- Fan parity gate: if fan hardware is detected but no RPM channels are decoded, UI surfaces an explicit parity-blocked status.
- Enabling privileged mode may trigger a macOS admin authentication prompt.
- Launching PulseBar does not auto-trigger administrator elevation; it first probes direct app-side IOHID channels, then reuses an already-running helper, and otherwise keeps the last-known sensor snapshot visible until you explicitly retry privileged sampling.
- Privileged mode now performs an immediate probe on enable/retry so status updates are not delayed until the next sampling tick.
- Helper payload now includes channel metadata (`temperatureCelsius` + `fanRPM`), source chain, and source diagnostics.
- Helper IPC now uses a user-scoped runtime directory with locked-down permissions and peer-UID validation instead of a world-writable fixed `/tmp` socket.
- If helper binary is missing, build it once:
  ```bash
  swift build --product PulseBarPrivilegedHelper
  ```
- If admin auth is unavailable/cancelled or helper communication fails, PulseBar remains operational and continues standard thermal-state monitoring.

## FPS and GPU Telemetry Notes

- GPU processor and memory percentages now come from private IOAccelerator / AGX `PerformanceStatistics` counters.
- FPS can use the live compositor frame stream from ScreenCaptureKit when enabled in Settings.
- Live compositor FPS capture is off by default.
- If ScreenCaptureKit cannot start because screen capture access is unavailable, PulseBar falls back to the display's live refresh rate and surfaces a status note in the CPU tab.

## Privileged Helper Target

Run helper manually (advanced/debug):

```bash
.build/debug/PulseBarPrivilegedHelper --socket "$TMPDIR/PulseBar/pulsebar-temp.sock" --expected-uid "$(id -u)"
```

## Disk Throughput Note

Disk read/write split now uses IOBlockStorageDriver cumulative byte counters where available.
If split counters are unavailable, PulseBar falls back to combined throughput via `iostat`.

## Fan Control Status

Fan write/control is not implemented.
Current roadmap status is a safety-gated feasibility track only; no fan control write path ships without explicit go/no-go criteria being met.

## Packaging for Local Usage

Unsigned local builds may trigger Gatekeeper warnings.
If needed for personal usage:
- Move app to `/Applications`
- Use Finder > Open (first run) to bypass quarantine prompts

## Documentation Index

- `/Users/Eric/Documents/system_monitor_app/docs/architecture.md`
- `/Users/Eric/Documents/system_monitor_app/docs/roadmap.md`
- `/Users/Eric/Documents/system_monitor_app/docs/dev-notes.md`
- `/Users/Eric/Documents/system_monitor_app/docs/agent-doc-maintenance.md`

## Testing

```bash
swift test
```

Covers ring buffer behavior, downsampling logic, units formatting, and alert-rule evaluation.
Additional tests cover detached-pane placement and hover-delay behavior, per-surface chart-window persistence, chart-window migration/bucketing rules, thermal-state mapping, temperature-history storage/rollups, memory-history storage/rollups/pruning, generic metric-history persistence, memory provider paging, native-pressure fallback behavior, metric-history migration cleanup for legacy pressure samples, process-memory parsing/cache fallback behavior, process-CPU parsing, composite privileged source fallback behavior, powermetrics parsing, profile-settings migration/backfill compatibility, metric codable/storage-key coverage (including associated interface metrics), battery/disk parser behavior, CPU user/system/idle samples, privileged IPC payloads (including legacy payload compatibility), and privileged provider channel/status metadata behavior.
