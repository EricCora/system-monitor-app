# Roadmap

## Objective

Reach practical iStat Menus parity for core system monitoring while preserving PulseBar's safety boundaries:

- local-only telemetry
- clear privileged/non-privileged separation
- no fan control writes unless the explicit safety gate passes

## Status Legend

- `Done`: implemented and shipped in current codebase
- `In Progress`: active implementation or active technical spike
- `Planned`: scoped and prioritized but not started
- `Deferred`: intentionally not targeted in near-term delivery

## Parity Progress Snapshot (as of 2026-03-06)

| Area | Tier | Status | Notes |
|------|------|--------|-------|
| Core metric pipeline + menu/popover UI (CPU, memory base, network aggregate, disk free+combined throughput, thermal state) | Foundation | `Done` | Provider model, sampling engine, and tabs are in place. |
| Privileged telemetry path (helper + IPC + fallback) | Foundation | `Done` | Privileged Celsius + fan telemetry are read-only and degrade safely. |
| Profiles + power-source auto-switch | Foundation | `Done` | Quiet/Balanced/Performance + Custom profile migration complete. |
| Alert engine v1 (CPU + temperature) | Foundation | `Done` | Threshold + duration + cooldown pattern is available for extension. |
| Temperature long-window history (`1h/24h/7d/30d`) | Foundation | `Done` | Persisted in `TemperatureHistoryStore` for sensor-level trend queries. |
| Temperature interaction parity (long sensor list, hover preview, click pin, hide/reset controls) | Foundation | `Done` | iStat-style detached adjacent history pane now ships with compact base popover temperature list. |
| Shared detached history panes | Foundation | `Done` | Temperature, Memory, and CPU now use the same adjacent pane controller for hover-preview + click-pin behavior. |
| Global refresh frequency + provider propagation | Foundation | `Done` | Refresh cadence is no longer profile-scoped and now propagates to privileged and subprocess-backed providers. |
| Persistent generic chart history across launches | Foundation | `Done` | CPU, battery, network, disk, FPS, and other plot-backed metrics persist in `MetricHistoryStore` for 30 days with natural gaps between sessions. |
| In-app alert delivery + recent alert log | Foundation | `Done` | Alerts now surface during `swift run` and continue sending notifications in app-bundle runtime. |
| Memory parity panel (pressure/memory/processes/swap/pages + detached history panes) | Foundation | `Done` | `MemoryTabView` now mirrors the compact iStat-style summary menu and hover-expanded pane model. |
| Memory long-window history (`1h/24h/7d/30d`) | Foundation | `Done` | Persisted in `MemoryHistoryStore` with rollups and downsampling. |
| CPU compact parity shell (usage/processes/GPU/FPS/load average/uptime + detached panes) | Foundation | `Done` | CPU menu now uses the same compact-summary + detached-history interaction model with live IOAccelerator GPU telemetry and ScreenCaptureKit compositor FPS capture (display-refresh fallback if screen capture access is unavailable). |
| Tier 1 execution plan + implementation pass | Tier 1 | `Done` | Tier 1 core parity set shipped in codebase. |
| Battery metrics (percent/state/rate/time/health) | 1.1 | `Done` | IOKit-based provider + Battery tab/menu integration. |
| Memory compressed + swap + paging metrics | 1.2 (phase 1) | `Done` | Memory provider now exposes compressed/swap totals plus page-in/page-out throughput. |
| Memory + disk alerts | 1.5 | `Done` | Alert engine supports both above and below comparators with Settings controls. |
| CPU load average (1/5/15 min) | 1.6 | `Done` | CPU provider appends load averages and UI surfaces values. |
| Disk S.M.A.R.T. status | 1.4 | `Done` | Disk tab displays parsed SMART status with graceful unknown handling. |
| Disk read/write split | 1.3 | `Done` | IOBlockStorageDriver counters as primary source; combined `iostat` fallback retained. |
| Network per-interface visibility | 1.7 | `Done` | Per-interface throughput telemetry and primary-interface UX added. |
| Tier 2 UX + advanced telemetry package | Tier 2 | `Planned` | Sparklines/themes/Wi-Fi+VPN/frequency-power/per-process GPU telemetry work. |
| Tier 3 stretch items (fan control, weather, clocks, per-app network/disk, etc.) | Tier 3 | `Deferred` | Fan control stays blocked on safety gate. |

## Tier 1 Delivery Plan (Concrete)

### Phase 1 (10 working days, ~2 weeks) - Completed

Goal: deliver the highest-value gaps with minimal architecture risk.

1. Battery provider + Battery tab + menu integration (`4d`)
2. Memory compressed/swap metrics + Memory tab updates (`2d`)
3. Alert engine extensions for memory pressure and disk free (`2d`)
4. CPU load average metrics + CPU tab/menu surface (`1d`)
5. Integration tests, settings wiring checks, docs refresh (`1d`)

### Phase 2 (9-10 working days, ~2 weeks) - Completed

Goal: complete remaining Tier 1 monitoring gaps.

1. Disk S.M.A.R.T. status collection + Disk tab badge/section (`1-2d`)
2. Disk read/write split source spike (API comparison + fallback decision) (`2d`)
3. Disk read/write implementation + regression checks (`2-3d`)
4. Network per-interface metrics + primary-interface UX (`2d`)
5. Validation/performance pass + docs/tests (`1-2d`)

### Phase 3 (5-7 working days, optional Tier 1.2 phase 2) - Planned

Goal: optional depth features after base Tier 1 parity is complete.

1. Per-process memory detail expansion (PID drill-in, more than top list) behind a settings toggle (`3-4d`)
2. Sampling-throttle guardrails + overhead instrumentation (`1-2d`)
3. UX cleanup for dense memory/process views (`1d`)

## Fan Control Feasibility Track (Safety-Gated)

- No direct fan write path is planned by default.
- Required go/no-go gate before any fan control coding:
  - public/system-supported control interface confirmation for target devices
  - bounded control + deterministic readback validation
  - watchdog/failsafe rollback-to-auto guarantees
  - conflict handling with external fan-control tooling
  - safety matrix pass under load/sleep/wake/error scenarios
- If gate criteria are not met:
  - keep fan control deferred
  - prioritize thermal alerts, profile automation, and cooling guidance UX

## Quality and UX Backlog (Post-Tier 1)

- compact/customizable menu layouts
- optional menu-bar sparklines
- advanced sensor presets (pinning profiles, import/export)
- launch-at-login diagnostics for unsigned/dev builds
- settings profile import/export
- optional provider plugin registration
- PulseBar self-overhead instrumentation panel
