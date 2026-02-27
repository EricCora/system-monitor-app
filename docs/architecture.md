# Architecture

## Design Goals

- Low-overhead periodic sampling
- Clear provider abstraction per metric category
- In-memory time-series optimized for rolling windows
- Persistent temperature-channel history for long windows
- UI decoupled from collection logic
- Local-only data model (no telemetry upload)

## High-Level Components

- `App/`
  - `PulseBarApp.swift`: `MenuBarExtra` app entry
  - `AppCoordinator.swift`: runtime orchestration, settings, profiles, launch-at-login, alerts
  - `TemperatureCoordinator.swift`: privileged temperature mode state/status bridge
  - `PowerSourceMonitor.swift`: AC/Battery change monitor for auto profile switching
  - `PrivilegedHelperTemperatureDataSource.swift`: app-side privileged helper launcher + IPC client

- `Core/`
  - `Models/`: `MetricID`, `MetricSample`, units, `TimeWindow`, `TemperatureHistoryWindow`, temperature channel telemetry models, thermal/profile models (`ThermalStateLevel`, `ProfileSettings`, `AppSettingsV2`)
  - `Privileged/`: shared privileged IPC contract (`PrivilegedTemperatureRequest`, `PrivilegedTemperatureResponse`)
  - `Storage/`: `RingBuffer`, `TimeSeriesStore`, `TemperatureHistoryStore` (SQLite-backed)
  - `Sampling/`: scheduler engine + downsampling

- `Providers/`
  - `CPUProvider`: Mach `host_processor_info` + `getloadavg(3)` load averages
  - `BatteryProvider`: IOKit `IOPowerSources` battery telemetry (charge/state/current/time/health/cycles)
  - `ThermalStateProvider`: `ProcessInfo.thermalState` -> qualitative thermal level metric
  - `MemoryProvider`: Mach `host_statistics64` + `vm.swapusage` swap used
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
  - Temperature tab sensor dashboard with grouped channels, source diagnostics, and selected-channel history (`1h/24h/7d/30d`)
  - Shared chart rendering
  - Settings form (profiles, privileged mode, alerts)

## Data Flow

1. `SamplingEngine` ticks at configured interval (`1s...10s`, default `2s`).
2. Providers sample concurrently.
3. Standard thermal-state samples are always available.
4. If privileged mode is enabled, app-side data source ensures helper availability and requests privileged samples over unix socket IPC.
5. Helper samples IOHID temperature services, probes AppleSMC fan channels, and falls back to `powermetrics` when temperature channels are still missing.
6. Helper returns rich channel payloads plus source diagnostics and active source chain metadata.
7. Privileged Celsius samples are emitted only when helper transport is healthy.
8. Privileged enable/retry actions trigger an immediate probe attempt to reduce status latency.
9. Batch is appended to `TimeSeriesStore`.
10. Latest privileged channels are persisted into `TemperatureHistoryStore` (SQLite) for long-window chart queries.
11. Batch is sent to `AlertEngine` for multi-rule evaluation.
12. Latest values, privileged status, channel diagnostics, and fan parity gate state are published to UI via `AppCoordinator`.
13. Tabs request windowed series and downsample for chart efficiency; temperature tab also queries persisted history windows (`1h/24h/7d/30d`).
14. `PowerSourceMonitor` transitions can update active profile when auto-switch rules are enabled.

## Thread Model

- Providers run off the UI thread in async sampling tasks.
- Time-series store is isolated as an actor.
- Temperature history persistence is isolated as an actor.
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
- Profile-controlled settings include sampling, menu visibility, graph window, throughput unit, and alert thresholds (CPU, temperature, memory pressure, disk free).
- Privileged temperature mode remains a global non-profile setting to avoid silent privilege changes during auto-switch.
- Legacy settings keys migrate into `AppSettingsV2` (`activeProfile: custom`, auto-switch off by default).

## Fan Control Boundary

- No fan write/control path exists in this architecture.
- Fan telemetry is read-only via AppleSMC probing; no control writes are implemented.

## Privileged Boundary

- Root-required telemetry does not run in the main app process.
- App remains functional in unprivileged mode when helper is unavailable.
- Helper remains read-only (temperature/power telemetry collection only, no control writes).
