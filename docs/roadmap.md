# Roadmap

## Delivered In Current Iteration

- Temperature tracking:
  - standard mode thermal-state metric (non-privileged)
  - optional privileged Celsius sampling via `powermetrics`
  - temperature dashboard tab and menu-bar temperature surface
  - privileged status/error visibility and safe fallback behavior

- Profiles:
  - built-in profiles: Quiet / Balanced / Performance
  - mutable Custom profile with migration from legacy settings
  - profile-aware settings persistence (`settings.v2`)
  - optional power-source auto-switch rules (AC/Battery mapping)

- Alerts:
  - multi-rule alert engine (CPU + optional temperature threshold rule)

## Next (V1 Continuing Backlog)

- Battery and power metrics:
  - charge percent
  - charging/discharging state
  - discharge rate
  - estimated remaining time

- Sensor and thermal depth:
  - richer privileged sensor inventory display/filtering
  - source confidence/caveat annotations per sensor family

- History persistence:
  - in-memory base interval for real-time
  - persisted multi-resolution windows: `1h/24h/7d/30d`

- Disk I/O improvement:
  - true read/write split counters (replace combined-only MVP path)

## Fan Control Feasibility Track (Safety-Gated)

- No direct fan write path is currently planned for implementation by default.
- Required go/no-go gate before any fan control coding:
  - public/system-supported control interface confirmation for target devices
  - bounded control + deterministic readback validation
  - watchdog/failsafe rollback-to-auto guarantees
  - conflict handling with external fan-control tooling
  - safety matrix pass under load/sleep/wake/error scenarios

- If gate criteria are not met:
  - keep fan control deferred
  - prioritize thermal alerts, profile automation, and cooling guidance UX

## Quality and UX

- More compact, customizable menu layouts
- Optional tiny sparklines in menu bar
- Sensor visibility filtering and pinning
- Better launch-at-login diagnostics for unsigned/dev builds

## Long-Term

- Import/export settings profiles
- Optional plugin-style provider registration
- Performance instrumentation panel for self-monitoring PulseBar overhead
