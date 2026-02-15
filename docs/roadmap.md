# Roadmap

## Next (V1)

- Battery and power metrics:
  - charge percent
  - charging/discharging state
  - discharge rate
  - estimated remaining time

- Sensor metrics:
  - non-privileged sensors where available
  - optional privileged mode using `powermetrics`

- Alert expansion:
  - multiple rules
  - per-metric rules
  - UI rule list management

- History persistence:
  - in-memory base interval for real-time
  - persisted multi-resolution windows: `1h/24h/7d/30d`

- Disk I/O improvement:
  - true read/write split counters (replace combined-only MVP path)

## Quality and UX

- More compact, customizable menu layouts
- Optional tiny sparklines in menu bar
- Sensor visibility filtering and pinning
- Better launch-at-login diagnostics for unsigned/dev builds

## Long-Term

- Import/export settings profiles
- Optional plugin-style provider registration
- Performance instrumentation panel for self-monitoring PulseBar overhead
