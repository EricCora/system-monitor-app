# Architecture

## Design Goals

- Low-overhead periodic sampling
- Clear provider abstraction per metric category
- In-memory time-series optimized for rolling windows
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
  - `Models/`: `MetricID`, `MetricSample`, units, `TimeWindow`, thermal/profile models (`ThermalStateLevel`, `ProfileSettings`, `AppSettingsV2`)
  - `Privileged/`: shared privileged IPC contract (`PrivilegedTemperatureRequest`, `PrivilegedTemperatureResponse`)
  - `Storage/`: `RingBuffer`, `TimeSeriesStore`
  - `Sampling/`: scheduler engine + downsampling

- `Providers/`
  - `CPUProvider`: Mach `host_processor_info`
  - `ThermalStateProvider`: `ProcessInfo.thermalState` -> qualitative thermal level metric
  - `MemoryProvider`: Mach `host_statistics64`
  - `NetworkProvider`: `getifaddrs` byte counters
  - `DiskProvider`: free bytes + combined throughput via `iostat`
  - `IOHIDTemperatureDataSource`: Apple Silicon HID-event Celsius sensor reader (privileged helper side)
  - `CompositeTemperatureDataSource`: IOHID-first fallback chain to `powermetrics`
  - `PowermetricsProvider`: privileged Celsius sampling provider with cache + retry backoff

- `PulseBarHelper/`
  - `PulseBarPrivilegedHelper`: root-required helper executable that samples IOHID Celsius sensors and falls back to `powermetrics`, responding over local unix socket IPC

- `Alerts/`
  - `AlertRule`
  - `AlertEngine` multi-rule threshold evaluator (CPU + temperature)

- `UI/`
  - Menu label summary
  - Popover dashboard tabs (CPU/Memory/Network/Temperature/Disk/Settings)
  - Shared chart rendering
  - Settings form (profiles, privileged mode, alerts)

## Data Flow

1. `SamplingEngine` ticks at configured interval (`1s...10s`, default `2s`).
2. Providers sample concurrently.
3. Standard thermal-state samples are always available.
4. If privileged mode is enabled, app-side data source ensures helper availability and requests privileged samples over unix socket IPC.
5. Helper samples IOHID temperature services first, then falls back to `powermetrics` when needed.
6. Privileged Celsius samples are emitted only when helper transport is healthy.
7. Privileged enable/retry actions trigger an immediate probe attempt to reduce status latency.
8. Batch is appended to `TimeSeriesStore`.
9. Batch is sent to `AlertEngine` for multi-rule evaluation.
10. Latest values and privileged status are published to UI via `AppCoordinator`.
11. Tabs request windowed series (`5m/15m/1h`) and downsample for chart efficiency.
12. `PowerSourceMonitor` transitions can update active profile when auto-switch rules are enabled.

## Thread Model

- Providers run off the UI thread in async sampling tasks.
- Time-series store is isolated as an actor.
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
- Profile-controlled settings include sampling, menu visibility, graph window, throughput unit, and alert thresholds.
- Privileged temperature mode remains a global non-profile setting to avoid silent privilege changes during auto-switch.
- Legacy settings keys migrate into `AppSettingsV2` (`activeProfile: custom`, auto-switch off by default).

## Fan Control Boundary

- No fan write/control path exists in this architecture.
- Fan-related work is currently limited to feasibility and safety-gate planning only.

## Privileged Boundary

- Root-required telemetry does not run in the main app process.
- App remains functional in unprivileged mode when helper is unavailable.
- Helper remains read-only (temperature/power telemetry collection only, no control writes).
