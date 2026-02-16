# PulseBar

PulseBar is a local macOS menu-bar system monitor built in Swift + SwiftUI.
It is an original implementation inspired by iStat-style capabilities, with no copied UI or branding.

## MVP Status

Implemented in this repo:
- Menu bar summary (CPU, Memory, Network, optional Disk)
- Popover dashboard tabs: CPU, Memory, Network, Temperature, Disk, Settings
- 5m / 15m / 1h history graphs with dynamic y-scaling
- Providers: CPU (Mach), Memory (Mach VM stats), Network (`getifaddrs`), Disk (free space + combined throughput from `iostat`)
- Temperature monitoring:
  - standard mode via `ProcessInfo.thermalState` (no privileges)
  - optional privileged mode via root helper + `powermetrics` (opt-in)
- Profiles: Quiet / Balanced / Performance / Custom
- Power-source auto-switch rules (AC and Battery profile mapping)
- Settings persistence via `UserDefaults` + `settings.v2` migration model
- Launch-at-login toggle using `SMAppService`
- Multi-rule alerts (CPU and optional temperature threshold alerts)
- Powermetrics provider with parser, retry backoff, and status reporting
- Privileged helper executable (`PulseBarPrivilegedHelper`) with local IPC contract

## Requirements

- macOS 13+
- Apple Silicon tested target (M1+)
- Swift 6 toolchain
- Full Xcode recommended for the app UX workflow
- Current developer machine reference: macOS 26.2 on M1 MacBook Pro

## Build and Run

### Option A: Swift Package (works with CLI toolchain)

```bash
swift build
swift run PulseBarApp
```

### Option B: Xcode

1. Install full Xcode.
2. Point developer tools to Xcode:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
3. Open the package/project in Xcode and run `PulseBarApp`.

## Launch at Login

PulseBar uses `SMAppService.mainApp`.
- In debug and unsigned contexts, registration may fail depending on launch location and signing.
- The Settings screen surfaces success/failure status text.

## Privileged Metrics (Optional Mode)
Privileged temperature sampling is optional and off by default.
- App process remains unprivileged; privileged sampling runs through `PulseBarPrivilegedHelper`.
- Helper command path: `/usr/bin/powermetrics` (sampler flags are selected by compatibility fallback logic).
- Enabling privileged mode may trigger a macOS admin authentication prompt.
- If helper binary is missing, build it once:
  ```bash
  swift build --product PulseBarPrivilegedHelper
  ```
- If admin auth is unavailable/cancelled or helper communication fails, PulseBar remains operational and continues standard thermal-state monitoring.

## Privileged Helper Target

Run helper manually (advanced/debug):

```bash
.build/debug/PulseBarPrivilegedHelper --socket /tmp/pulsebar-temp.sock
```

## Disk Throughput Note

Current macOS `iostat` output is used for **combined throughput** only in MVP. Read/write split is deferred to V1.

## Fan Control Status

Fan write/control is not implemented.
Current roadmap status is a safety-gated feasibility track only; no fan control write path ships without explicit go/no-go criteria being met.

## Packaging for Local Usage

Unsigned local builds may trigger Gatekeeper warnings.
If needed for personal usage:
- Move app to `/Applications`
- Use Finder > Open (first run) to bypass quarantine prompts

## Documentation Index

- `/Users/Eric/Documents/system_monitor_app/docs/architecture.md`
- `/Users/Eric/Documents/system_monitor_app/docs/roadmap.md`
- `/Users/Eric/Documents/system_monitor_app/docs/dev-notes.md`
- `/Users/Eric/Documents/system_monitor_app/docs/agent-doc-maintenance.md`

## Testing

```bash
swift test
```

Covers ring buffer behavior, downsampling logic, units formatting, and alert-rule evaluation.
Additional tests cover thermal-state mapping, powermetrics parsing, profile-settings migration, privileged IPC payloads, and privileged provider caching/degradation behavior.
