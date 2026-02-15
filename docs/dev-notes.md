# Developer Notes

## Known API Caveats

- Primary target environment for current development: macOS 26.2 on M1 MacBook Pro.
- `DiskProvider` currently parses `/usr/sbin/iostat -d -K -c 2`.
- On this macOS flavor, iostat exposes combined throughput columns, not explicit read/write split.
- Launch-at-login via `SMAppService` can fail in unsigned/debug contexts.
- Notification delivery requires user authorization.

## Performance Guardrails

- Sampling runs on async tasks, not the UI thread.
- Chart input is downsampled to avoid heavy redraws.
- Windowed retrieval is bounded by ring-buffer capacity.
- Dashboard navigation uses a segmented control instead of `TabView` to avoid popover tab focus/interaction glitches on some macOS menu-bar runtimes.

## Implementation Defaults

- Sample interval default: `2s`
- Sample interval range: `1...10s`
- Windows: `5m`, `15m`, `1h`
- In-memory history only for MVP
- Throughput display default: `Bytes/s`

## Future Powermetrics Plan

- Keep privileged mode fully opt-in.
- Clearly disclose command usage and required privileges.
- Parse-only helper must fail safely and keep app operational without admin mode.
