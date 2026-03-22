# Architecture

## Design Goals

- Low-overhead periodic sampling
- Clear provider abstraction per metric category
- In-memory time-series optimized for rolling windows
- Persistent temperature-channel history for long windows
- Persistent memory-composition history for long windows
- Persistent generic metric history for chart-backed samples across launches
- UI decoupled from collection logic
- Local-only data model (no telemetry upload)

## High-Level Components

- `App/`
  - `PulseBarApp.swift`: `MenuBarExtra` app entry
  - `AppCoordinator.swift`: thin composition root that wires services, providers, sampling, alerts, launch-at-login, persistent history hydration, dashboard/menu bar presentation stores, compact-surface caches, and detached-pane history snapshots
  - `Services/SettingsController.swift`: profile-controlled settings ownership, per-surface chart-window persistence, dashboard/menu bar preferences, sensor favorites/presets, visible-window preferences, and alert/profile rules
  - `Services/TelemetryStore.swift`: presentation-layer latest values, revisions, provider failures, process lists, GPU/FPS summaries, alerts, and privileged temperature status
  - `Services/TemperaturePaneModel.swift`: selected/hidden temperature-sensor state plus detached-pane selection rules
  - `Services/HistorySnapshots.swift`: grouped detached-pane history snapshot models for CPU and memory panes
  - `Services/DashboardContext.swift`: dashboard-only context enrichment for network identity (active interface, SSID, VPN heuristics, private IP addresses)
  - `AlertDeliveryCenter.swift`: in-app recent-alert log plus system-notification fanout
  - `TemperatureCoordinator.swift`: privileged temperature mode state/status bridge
  - `DetachedMetricsPaneController.swift`: shared detached AppKit panel lifecycle + hover/pin visibility coordination for temperature, memory, and CPU history panes
  - `PowerSourceMonitor.swift`: AC/Battery change monitor for auto profile switching
  - `PrivilegedHelperTemperatureDataSource.swift`: app-side privileged helper launcher + IPC client

- `Core/`
  - `Models/`: `MetricID`, `MetricSample`, units, shared `ChartWindow`, legacy window migration helpers, dashboard/menu configuration models, CPU summary/process models, temperature channel telemetry models, sensor preset models, thermal/profile models (`ThermalStateLevel`, `ProfileSettings`, `AppSettingsV2`, `AppSettingsV3`, `AppSettingsV4`)
  - `Privileged/`: shared privileged IPC contract (`PrivilegedTemperatureRequest`, `PrivilegedTemperatureResponse`) plus helper connection configuration
  - `Storage/`: `RingBuffer`, `TimeSeriesStore`, `TemperatureHistoryStore` (SQLite-backed), `MemoryHistoryStore` (SQLite-backed), `MetricHistoryStore` (SQLite-backed generic chart persistence)
  - `Sampling/`: scheduler engine + downsampling + structured `SamplingBatch`/`ProviderFailure` results

- `Providers/`
  - `CPUProvider`: Mach `host_processor_info` + user/system/idle split + per-core load + `getloadavg(3)` + uptime
  - `BatteryProvider`: IOKit `IOPowerSources` battery telemetry (charge/state/current/time/health/cycles)
  - `ThermalStateProvider`: `ProcessInfo.thermalState` -> qualitative thermal level metric
  - `MemoryProvider`: Mach `host_statistics64` + `vm.swapusage` with memory composition fields (app/wired/active/compressed/cache), swap totals, and page-in/page-out throughput rates
  - `ProcessCPUProvider`: cached `ps`-based top-process CPU list for CPU parity panel
  - `ProcessMemoryProvider`: cached `ps`-based top-process memory list for parity process panel
  - `GPUStatsProvider`: GPU summary provider backed by private IOAccelerator / AGX `PerformanceStatistics` counters for processor and memory usage
  - `FPSProvider`: ScreenCaptureKit compositor-frame sampler with display-refresh fallback and CPU-tab status reporting when screen capture access is unavailable
  - `NetworkProvider`: `getifaddrs` aggregate + per-interface byte counters
  - `DiskProvider`: free bytes + S.M.A.R.T. status + read/write throughput via IOBlockStorageDriver stats (`iostat` combined fallback)
  - `IOHIDTemperatureDataSource`: Apple Silicon HID-event Celsius sensor reader (privileged helper side)
  - `CompositeTemperatureDataSource`: compatibility fallback chain for privileged temperature reads
  - `PowermetricsProvider`: privileged Celsius sampling provider with cache + retry backoff

- `PulseBarHelper/`
  - `PulseBarPrivilegedHelper`: helper executable that samples IOHID Celsius sensors, probes AppleSMC fan telemetry, falls back to `powermetrics`, and responds over local unix socket IPC
  - `PulseBarSMCBridge`: native C bridge for AppleSMC fan RPM keys

- `Alerts/`
  - `AlertRule`
  - `AlertEngine` multi-rule threshold evaluator with above/below comparators (CPU, temperature, native macOS memory pressure, disk free)

- `UI/`
  - Menu bar summary v2 with compact / balanced / dense layouts and per-metric text, icon, or sparkline rendering
  - Overview-first popover navigation with `Overview`, `CPU`, `Memory`, `Battery`, `Network`, `Temperature`, `Disk`, and `Settings` sections
  - `Overview` renders the card dashboard (CPU & GPU, Memory, Battery, Network, Disk, Sensors) with shared rounded-card primitives, hero values, compact gauges, and short supporting lists
  - Detailed sections reuse the existing CPU/memory/battery/network/temperature/disk module views, chart-window pickers, and detached-pane hover/pin interactions, now themed with the same shared light palette used by `Overview`
  - Sensors overview card supports favorites-first curation, preset switching, and a direct drill-down into the restored temperature detail surface
  - Dashboard cards reuse prepared compact CPU/memory/network/battery/temperature surface models rather than rebuilding large live charts every tick
  - Shared chart rendering through `ChartSeriesPipeline` and detached chart viewport overlays (single sanitization boundary, stable series identity, shared y-domain policy, shared hover/zoom interactions)
  - Temperature detail view combines always-available thermal-state history with aggregate primary/maximum temperature traces when metric history exists, while per-sensor detached panes remain reserved for real privileged/hydrated sensor channels
  - Full sidebar-based settings window for detailed configuration of profiles, dashboard layout/order, menu bar display styles, alerts, and sensor presets

## Data Flow

1. `SamplingEngine` ticks at configured global interval (`1s...10s`, default `2s`).
2. Providers sample concurrently and `SamplingEngine` captures both successful samples and per-provider failures.
3. Standard thermal-state samples are always available.
4. If enhanced temperature mode is enabled, the app first attempts a direct app-side IOHID temperature probe on launch.
5. If direct IOHID is unavailable, app-side data source checks for an already-running helper in a user-scoped runtime directory and only launches with elevation on explicit retry/enable.
6. Helper samples IOHID temperature services, probes AppleSMC fan channels, and falls back to `powermetrics` when temperature channels are still missing.
7. Helper validates the connecting peer UID before serving requests, then returns rich channel payloads plus source diagnostics and active source chain metadata.
8. Direct IOHID or helper-backed Celsius samples both flow through the same live telemetry/snapshot pipeline, so overview and detail surfaces stay source-agnostic.
9. Privileged enable/retry actions trigger an immediate probe attempt to reduce status latency.
10. Batch is appended to `TimeSeriesStore` for low-latency in-memory use and to `MetricHistoryStore` for persistent chart history.
11. `MetricHistoryStore` maintains a small `latest_metric_samples` cache table so startup hydration can restore newest persisted values without grouping the full metric history table, and applies one-time data cleanup when a metric's stored semantics change.
12. `AppCoordinator` snapshots memory composition into `MemoryHistoryStore`, updates feature-scoped dashboard/menu bar stores, refreshes dashboard-only context (network identity and battery energy summaries), and keeps compact rolling CPU/Battery/Network/Disk series warm without re-querying SQLite on every visible tick.
13. CPU and memory process polling are driven by actual surface visibility with their own cadence, rather than piggybacking on the global sample loop.
14. Latest privileged channels are persisted into `TemperatureHistoryStore` (SQLite) for long-window sensor chart queries, while a separate latest-temperature snapshot is stored in `UserDefaults` for quiet startup hydration.
15. Batch is sent to `AlertEngine` for multi-rule evaluation; alert results are mirrored into `AlertDeliveryCenter` so alerts remain visible during `swift run`.
16. `TelemetryStore` publishes latest values, provider failures, history revision tokens, privileged status, channel diagnostics, fan parity gate state, recent alerts, and process status.
17. The popover dashboard and menu bar observe narrower surface stores, while detached panes request grouped CPU/memory history snapshots keyed by window/selection/revision and coalesce updates during hover/zoom interaction.
18. `PowerSourceMonitor` transitions can update the active profile through `SettingsController` auto-switch rules.

## Thread Model

- Providers run off the UI thread in async sampling tasks.
- Time-series store is isolated as an actor.
- Temperature history persistence is isolated as an actor.
- Memory history persistence is isolated as an actor.
- Generic metric history persistence is isolated as an actor.
- UI updates happen on `MainActor`.
- Alert evaluation is actor-isolated.

## Extensibility

To add a new metric category:
1. Implement `MetricProvider`.
2. Add new `MetricID` entries.
3. Register provider in `AppCoordinator`.
4. Add dashboard/menu surface as needed.
5. Update docs and tests.

## Profile System Notes

- Built-in profiles: `Quiet`, `Balanced`, `Performance`; user editable profile: `Custom`.
- Profile-controlled settings include menu visibility, throughput unit, chart appearance, and alert thresholds (CPU, temperature, memory pressure, disk free).
- Chart windows are per-surface UI preferences, not profile-controlled settings.
- Refresh cadence is global (`AppSettingsV4.globalSamplingInterval`) so profile switches do not silently alter sampling rate.
- Privileged temperature mode remains a global non-profile setting to avoid silent privilege changes during auto-switch.
- Legacy settings keys migrate into `AppSettingsV4` (`activeProfile: custom`, auto-switch off by default) while preserving dashboard/menu bar defaults for older installs.

## Fan Control Boundary

- No fan write/control path exists in this architecture.
- Fan telemetry is read-only via AppleSMC probing; no control writes are implemented.

## Privileged Boundary

- Root-required telemetry does not run in the main app process.
- App remains functional in unprivileged mode when helper is unavailable.
- Helper remains read-only (temperature/power telemetry collection only, no control writes).
- Helper IPC is locked to the current user via a private runtime directory, `0600` socket permissions, and peer-credential validation before serving requests.
