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
  - `AppCoordinator.swift`: runtime orchestration, settings/profile migration, launch-at-login, persistent history hydration, alerts, CPU/memory/temperature parity state
  - `AlertDeliveryCenter.swift`: in-app recent-alert log plus system-notification fanout
  - `TemperatureCoordinator.swift`: privileged temperature mode state/status bridge
  - `DetachedMetricsPaneController.swift`: shared detached AppKit panel lifecycle + hover/pin visibility coordination for temperature, memory, and CPU history panes
  - `PowerSourceMonitor.swift`: AC/Battery change monitor for auto profile switching
  - `PrivilegedHelperTemperatureDataSource.swift`: app-side privileged helper launcher + IPC client

- `Core/`
  - `Models/`: `MetricID`, `MetricSample`, units, `TimeWindow`, `MetricHistoryWindow`, `TemperatureHistoryWindow`, `MemoryHistoryWindow`, menu layout/config models, CPU summary/process models, temperature channel telemetry models, thermal/profile models (`ThermalStateLevel`, `ProfileSettings`, `AppSettingsV2`, `AppSettingsV3`)
  - `Privileged/`: shared privileged IPC contract (`PrivilegedTemperatureRequest`, `PrivilegedTemperatureResponse`)
  - `Storage/`: `RingBuffer`, `TimeSeriesStore`, `TemperatureHistoryStore` (SQLite-backed), `MemoryHistoryStore` (SQLite-backed), `MetricHistoryStore` (SQLite-backed generic chart persistence)
  - `Sampling/`: scheduler engine + downsampling

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
  - `AlertEngine` multi-rule threshold evaluator with above/below comparators (CPU, temperature, memory pressure, disk free)

- `UI/`
  - Menu label summary
  - Popover dashboard tabs (CPU/Memory/Battery/Network/Temperature/Disk/Settings)
  - Temperature tab parity layout with long grouped sensor list in the compact popover plus a detached adjacent history pane (hover-preview + click-pin, hide/reset controls, source diagnostics)
  - Memory tab parity layout with compact pressure/memory/process/swap/pages summary sections and detached history panes (`1h/24h/7d/30d`)
  - CPU tab parity layout with compact CPU/process/GPU/FPS/load-average/uptime sections and detached history panes (`1h/24h/7d/30d`)
  - Shared chart rendering
  - Settings form (profiles, global refresh frequency, layout config, privileged mode, alerts, recent-alert history)

## Data Flow

1. `SamplingEngine` ticks at configured global interval (`1s...10s`, default `2s`).
2. Providers sample concurrently.
3. Standard thermal-state samples are always available.
4. If privileged mode is enabled, app-side data source ensures helper availability and requests privileged samples over unix socket IPC.
5. Helper samples IOHID temperature services, probes AppleSMC fan channels, and falls back to `powermetrics` when temperature channels are still missing.
6. Helper returns rich channel payloads plus source diagnostics and active source chain metadata.
7. Privileged Celsius samples are emitted only when helper transport is healthy.
8. Privileged enable/retry actions trigger an immediate probe attempt to reduce status latency.
9. Batch is appended to `TimeSeriesStore` for low-latency in-memory use and to `MetricHistoryStore` for persistent chart history.
10. `AppCoordinator` snapshots memory composition into `MemoryHistoryStore`, refreshes cached top process CPU/memory entries, refreshes GPU summary state, and publishes FPS capture status for the CPU tab.
11. Latest privileged channels are persisted into `TemperatureHistoryStore` (SQLite) for long-window sensor chart queries.
12. Batch is sent to `AlertEngine` for multi-rule evaluation; alert results are mirrored into `AlertDeliveryCenter` so alerts remain visible during `swift run`.
13. Latest values, hydrated persisted values, privileged status, channel diagnostics, fan parity gate state, recent alerts, and process status are published to UI via `AppCoordinator`.
14. Tabs request windowed series from persistent stores and downsample for chart efficiency; detached panes render temperature, memory, and CPU long-window history from coordinator state.
15. `PowerSourceMonitor` transitions can update active profile when auto-switch rules are enabled.

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
4. Add tab/menu surface as needed.
5. Update docs and tests.

## Profile System Notes

- Built-in profiles: `Quiet`, `Balanced`, `Performance`; user editable profile: `Custom`.
- Profile-controlled settings include menu visibility, graph window, throughput unit, and alert thresholds (CPU, temperature, memory pressure, disk free).
- Refresh cadence is now global (`AppSettingsV3.globalSamplingInterval`) so profile switches do not silently alter sampling rate.
- Privileged temperature mode remains a global non-profile setting to avoid silent privilege changes during auto-switch.
- Legacy settings keys migrate into `AppSettingsV3` (`activeProfile: custom`, auto-switch off by default).

## Fan Control Boundary

- No fan write/control path exists in this architecture.
- Fan telemetry is read-only via AppleSMC probing; no control writes are implemented.

## Privileged Boundary

- Root-required telemetry does not run in the main app process.
- App remains functional in unprivileged mode when helper is unavailable.
- Helper remains read-only (temperature/power telemetry collection only, no control writes).
