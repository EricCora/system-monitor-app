# Developer Notes

## Known API Caveats

- Primary target environment for current development: macOS 26.2 on M1 MacBook Pro.
- `DiskProvider` currently parses `/usr/sbin/iostat -d -K -c 2`.
- On this macOS flavor, iostat exposes combined throughput columns, not explicit read/write split.
- Standard temperature mode is `ProcessInfo.thermalState` (qualitative and coarse, not direct Celsius).
- Optional privileged temperature mode executes `/usr/bin/powermetrics --samplers smc -n 1 -i 1000`.
- Privileged temperature parser is best-effort and can drift with OS/hardware output changes.
- Launch-at-login via `SMAppService` can fail in unsigned/debug contexts.
- Notification delivery requires user authorization.

## Performance Guardrails

- Sampling runs on async tasks, not the UI thread.
- Chart input is downsampled to avoid heavy redraws.
- Windowed retrieval is bounded by ring-buffer capacity.
- Dashboard navigation uses a segmented control instead of `TabView` to avoid popover tab focus/interaction glitches on some macOS menu-bar runtimes.
- Privileged temperature collection is throttled with cache (`5s`) and retry backoff (`5s`, `15s`, `30s`, `60s`) after failures.

## Implementation Defaults

- Sample interval default: `2s`
- Sample interval range: `1...10s`
- Windows: `5m`, `15m`, `1h`
- Profiles: Quiet / Balanced / Performance / Custom
- Auto-switch rules default: disabled; AC -> Balanced, Battery -> Quiet
- Privileged temperature mode default: disabled
- In-memory history only
- Throughput display default: `Bytes/s`
- Temperature alert default: disabled, threshold `92 C`, duration `20s`

## Privileged Temperature Failure Modes

- Permission denied / unavailable command
- Timeout or non-zero command exit
- Parser unable to extract valid Celsius values
- Empty sensor set from command output

All failures degrade to standard thermal-state tracking while the app remains operational.

## Fan Control Status

- Direct fan write/control is explicitly deferred.
- Any future implementation requires safety-gate criteria and public/system interface validation before code-level control paths are added.
