# PulseBar

PulseBar is a local macOS menu-bar system monitor built in Swift + SwiftUI.
It is an original implementation inspired by iStat-style capabilities, with no copied UI or branding.

## MVP Status

Implemented in this repo:
- Menu bar summary (CPU, Memory, Network, optional Disk)
- Popover dashboard tabs: CPU, Memory, Network, Disk, Settings
- 5m / 15m / 1h history graphs with dynamic y-scaling
- Providers: CPU (Mach), Memory (Mach VM stats), Network (`getifaddrs`), Disk (free space + combined throughput from `iostat`)
- Settings persistence via `UserDefaults`
- Launch-at-login toggle using `SMAppService`
- Basic CPU alert rule (`CPU > threshold for duration`) with local notifications
- Powermetrics provider scaffold (no active privileged sampling in MVP)

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

## Privileged Metrics (Scaffold in MVP)

`PowermetricsProvider` is intentionally scaffold-only in MVP.
Future privileged mode will be opt-in and transparent about command usage (`/usr/bin/powermetrics`).

## Disk Throughput Note

Current macOS `iostat` output is used for **combined throughput** only in MVP. Read/write split is deferred to V1.

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
