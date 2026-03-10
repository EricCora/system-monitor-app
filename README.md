# PulseBar

PulseBar is a local macOS menu-bar system monitor built in Swift + SwiftUI.
It is an original implementation inspired by iStat-style capabilities, with no copied UI or branding.

## MVP Status

Implemented in this repo:
- Menu bar summary (CPU, Memory, Battery, Network, optional Disk/Temperature)
- Popover dashboard tabs: CPU, Memory, Battery, Network, Temperature, Disk, Settings
- Unified chart windows across compact tabs and detached panes: 15m / 1h / 6h / 1d / 1w / 1mo
- Persistent chart history across launches with shared chart-window rollups for metric, memory, and temperature history
- Generic metric history persistence: CPU, battery, network, disk, FPS, and other plot-backed samples persist for 30 days while preserving offline gaps between sessions
- Providers: CPU (Mach user/system/idle + per-core + load average + uptime), Battery (IOKit power sources), Memory (Mach VM stats + native macOS pressure level + swap usage + paging rates), Process CPU (`ps` top list with cache), Process memory (`ps` top list with cache), Network (`getifaddrs` aggregate + per-interface), Disk (free space + IOBlockStorageDriver read/write + SMART with combined fallback), FPS (ScreenCaptureKit compositor frame stream with display-refresh fallback when screen capture access is unavailable), GPU summary (private IOAccelerator/AGX performance statistics for processor + memory usage)
- Temperature monitoring:
  - standard mode via `ProcessInfo.thermalState` (no privileges)
  - privileged mode via helper source chain: IOHID temperature sensors + AppleSMC fan probe + `powermetrics` fallback
  - iStat-style temperature tab with compact sensor list plus a detached adjacent history pane (hover preview, click pinning, hide/reset sensor controls, shared chart windows, drag-to-zoom, double-click reset)
- Memory tab parity panel: compact pressure/memory/process/swap/pages summary menu with detached hover-expanded history panes
- CPU tab parity panel: compact CPU/process/GPU/FPS/load-average/uptime summary menu with detached hover-expanded history panes
  - compact CPU usage/load charts use prepared rolling render models rather than live Swift Charts rebuilds
  - startup latest-sample hydration uses a maintained latest-metric cache table instead of grouping the full metric history database on launch
- Profiles: Quiet / Balanced / Performance / Custom
- Power-source auto-switch rules (AC and Battery profile mapping)
- Settings persistence via `UserDefaults` + `settings.v3` migration model, including per-surface chart-window memory and visible-window preferences
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
- Privileged mode now performs an immediate probe on enable/retry so status updates are not delayed until the next sampling tick.
- Helper payload now includes channel metadata (`temperatureCelsius` + `fanRPM`), source chain, and source diagnostics.
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
.build/debug/PulseBarPrivilegedHelper --socket /tmp/pulsebar-temp.sock
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
