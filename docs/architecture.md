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
  - `AppCoordinator.swift`: runtime orchestration, settings, launch-at-login, alerts

- `Core/`
  - `Models/`: `MetricID`, `MetricSample`, units, `TimeWindow`
  - `Storage/`: `RingBuffer`, `TimeSeriesStore`
  - `Sampling/`: scheduler engine + downsampling

- `Providers/`
  - `CPUProvider`: Mach `host_processor_info`
  - `MemoryProvider`: Mach `host_statistics64`
  - `NetworkProvider`: `getifaddrs` byte counters
  - `DiskProvider`: free bytes + combined throughput via `iostat`
  - `PowermetricsProvider`: scaffold for future privileged mode

- `Alerts/`
  - `AlertRule`
  - `AlertEngine` threshold evaluator

- `UI/`
  - Menu label summary
  - Popover dashboard tabs
  - Shared chart rendering
  - Settings form

## Data Flow

1. `SamplingEngine` ticks at configured interval (`1s...10s`, default `2s`).
2. Providers sample concurrently.
3. Batch is appended to `TimeSeriesStore`.
4. Batch is sent to `AlertEngine` for rule evaluation.
5. Latest values are published to UI via `AppCoordinator`.
6. Tabs request windowed series (`5m/15m/1h`) and downsample for chart efficiency.

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
