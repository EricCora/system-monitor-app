# PulseBar → iStat Menus Parity: Prioritized Improvement Proposal

This document outlines a prioritized roadmap for bringing PulseBar closer to iStat Menus feature parity. It considers macOS APIs, PulseBar's existing architecture (providers, actors, privileged helper), safety/privilege boundaries, and scope suitable for a solo/small team.

---

## Tier 1 — High Impact, Feasible

*Core monitoring gaps that most users expect from a system monitor.*

### 1.1 Battery & Power Metrics

| Field | Details |
|-------|---------|
| **Description** | Charge percent, charging/discharging state, discharge rate (mA), estimated time remaining, battery health (max/design capacity ratio). |
| **PulseBar Gap** | No battery metrics. `PowerSourceMonitor` only tracks AC vs Battery for profile auto-switch; no charge %, rate, or health. |
| **Suggested Approach** | Add `BatteryProvider` using IOKit `IOPowerSources` API (`IOPSCopyPowerSourcesInfo`, `IOPSGetPowerSourceDescription`). Keys: `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSDesignCapacityKey`, `kIOPSPowerSourceStateKey`, `kIOPSCurrentKey` (mA), `kIOPSIsChargingKey`, `kIOPSTimeToEmptyKey`, `kIOPSTimeToFullChargeKey`. Non-privileged; works in main app. Add `MetricID` entries and a Battery tab. |
| **Complexity** | **M** — IOKit API is well-documented; UI and persistence for health/cycle count are straightforward. |

---

### 1.2 Memory: Compressed, Swap, Per-App

| Field | Details |
|-------|---------|
| **Description** | Show compressed memory, swap usage, and optionally per-app memory breakdown. |
| **PulseBar Gap** | Memory tab shows only used/free/pressure. `vm_statistics64` already exposes `compressor_page_count`; swap is available via `sysctl vm.swapusage` (total/used/free). Per-app requires `libproc`/`task_info` and is heavier. |
| **Suggested Approach** | **Phase 1 (S):** Add `memoryCompressedBytes`, `memorySwapBytes` to `MetricID`; extend `MemoryProvider` with `vmStats.compressor_page_count` and `sysctl vm.swapusage` for swap used. Update Memory tab UI. **Phase 2 (M):** Per-app memory via `libproc`/`task_info` — consider optional toggle due to CPU cost; may need sampling throttling. |
| **Complexity** | **S** for compressed+swap; **M** for per-app. |

---

### 1.3 Disk: Read/Write Split

| Field | Details |
|-------|---------|
| **Description** | Separate read and write throughput instead of combined only. |
| **PulseBar Gap** | `DiskProvider` uses `iostat -d -K -c 2` and sums combined MB/s. Roadmap already calls this out. |
| **Suggested Approach** | macOS `iostat` does not expose read/write split in standard output. Options: (1) Parse `iostat -o` (sectors/transfers) and correlate with `diskutil` or kernel stats if available; (2) Use `fs_usage` or `iotop`-style tools (privileged, heavier); (3) Check `sysctl`/`IOKit` for block device read/write counters. **Pragmatic path:** Investigate `diskutil info` or `system_profiler SPSerialATADataType` for per-disk stats; fallback to combined if no clean API. Alternative: `vm_stat`-style IOKit or `libkern` disk stats. |
| **Complexity** | **M** — macOS lacks a simple `iostat -x`-style split; may require Process/IOKit spelunking. |

---

### 1.4 Disk: S.M.A.R.T. Status

| Field | Details |
|-------|---------|
| **Description** | Basic S.M.A.R.T. health status (e.g., Verified / Failing / Not Supported). |
| **PulseBar Gap** | No disk health visibility. |
| **Suggested Approach** | Run `diskutil info <disk>` and parse "SMART Status" line. Non-privileged. For detailed S.M.A.R.T. data, `smartmontools` is third-party; stick to `diskutil` for parity with Disk Utility. Add optional Disk tab section or badge. |
| **Complexity** | **S** — Simple `Process` + regex/parsing. |

---

### 1.5 Alerts: Memory & Disk

| Field | Details |
|-------|---------|
| **Description** | Alert when memory pressure or disk free space crosses thresholds. |
| **PulseBar Gap** | `AlertEngine` supports only CPU and temperature (`AlertRule.metricID`). |
| **Suggested Approach** | Extend `AlertRule` and `AlertEngine` to support `memoryPressureLevel`, `memoryUsedBytes`, `diskFreeBytes`. Add UI in Settings for new rules. Reuse existing duration/cooldown logic. |
| **Complexity** | **S** — Same pattern as CPU/temperature alerts. |

---

### 1.6 CPU Load Average

| Field | Details |
|-------|---------|
| **Description** | Display 1/5/15-minute load average (classic Unix metric). |
| **PulseBar Gap** | CPU tab shows per-core and total percent only; no load average. |
| **Suggested Approach** | `getloadavg(3)` — trivial. Add `MetricID.cpuLoadAverage1` (or composite). Expose in CPU tab and optionally in menu bar. |
| **Complexity** | **S** — Single syscall. |

---

### 1.7 Network: Per-Interface (Optional Split)

| Field | Details |
|-------|---------|
| **Description** | Show throughput per interface (Wi‑Fi vs Ethernet) or at least identify active interface. |
| **PulseBar Gap** | `NetworkProvider` aggregates all non-loopback interfaces via `getifaddrs`. |
| **Suggested Approach** | Extend `readCounters()` to return per-interface breakdown (interface name + bytes). Add `MetricID.networkInterfaceInBytesPerSec(name)`, `networkInterfaceOutBytesPerSec(name)` or a structured metric. UI can show primary interface or expandable list. |
| **Complexity** | **M** — Same `getifaddrs` loop; need to key by `ifa_name` and handle interface renames. |

---

## Tier 2 — Medium Impact

*Enhanced monitoring and UX improvements.*

### 2.1 CPU/GPU Frequency (Privileged)

| Field | Details |
|-------|---------|
| **Description** | Per-core CPU frequency, GPU frequency (where available). |
| **PulseBar Gap** | No frequency data. `powermetrics` exposes frequency distribution; IOHID/SMC may have additional data. |
| **Suggested Approach** | Extend privileged helper / `PowermetricsProvider` to parse `powermetrics` output for CPU/GPU frequency. `powermetrics --samplers cpu_power` includes frequency info. Add `MetricID` for frequency; display in CPU/Temperature tabs. |
| **Complexity** | **M** — Parsing powermetrics output; format varies by macOS version. |

---

### 2.2 GPU Utilization & FPS

| Field | Details |
|-------|---------|
| **Description** | GPU usage percent and/or FPS for active display. |
| **PulseBar Gap** | No GPU metrics. |
| **Suggested Approach** | `powermetrics --samplers gpu_power` provides GPU activity. FPS typically requires Metal/DisplayLink or `CGDisplayMode` refresh rate (static). For dynamic FPS, would need display capture — high complexity. Start with GPU utilization from powermetrics. |
| **Complexity** | **M** for GPU utilization; **L** for true FPS. |

---

### 2.3 Sensors: Voltage, Current, Power (Privileged)

| Field | Details |
|-------|---------|
| **Description** | Voltage, current, and power from powermetrics/SMC. |
| **PulseBar Gap** | Temperature and fan RPM only. Powermetrics reports estimated power for CPU/GPU/ANE. |
| **Suggested Approach** | Parse `powermetrics` power output (mW); extend `PowermetricsTemperatureReading` or add `PowerReading` with CPU/GPU/ANE power. SMC can expose voltage/current on some Macs. Add to Temperature tab or new "Power" section. |
| **Complexity** | **M** — Extend existing powermetrics parsing. |

---

### 2.4 Network: Wi-Fi SSID, VPN Indicator

| Field | Details |
|-------|---------|
| **Description** | Show connected Wi-Fi network name and VPN status. |
| **PulseBar Gap** | No network identity info. |
| **Suggested Approach** | **Wi-Fi:** `CoreWLAN.CWWiFiClient.shared().interface()?.ssid()` — requires Location Services permission on Sonoma+. **VPN:** Check `SCNetworkReachability` or `ifconfig` for `utun`/`ipsec` interfaces; or parse `scutil --nc list` for VPN service names. Add to Network tab as contextual info. |
| **Complexity** | **M** — Permission handling for Wi-Fi; VPN detection is heuristic. |

---

### 2.5 Sparklines in Menu Bar

| Field | Details |
|-------|---------|
| **Description** | Mini sparkline charts in menu bar for CPU, memory, etc. |
| **PulseBar Gap** | Menu bar shows only current values (text). Roadmap mentions "Optional tiny sparklines." |
| **Suggested Approach** | Add `SparklineView` using `TimeSeriesStore` windowed data. Render as small `Path` or `Canvas` in `MenuBarSummaryView`. Keep configurable per-metric via profile. |
| **Complexity** | **M** — UI work; ensure low overhead for menu bar updates. |

---

### 2.6 Combined Menu Mode / Compact Layout

| Field | Details |
|-------|---------|
| **Description** | Single compact menu bar item with dropdown, or configurable multi-item layout. |
| **PulseBar Gap** | Single `MenuBarExtra` with horizontal HStack of metrics. |
| **Suggested Approach** | Add profile option for "compact" vs "expanded" menu layout. Consider `MenuBarExtra` with `Label` that shows one primary metric + chevron; popover shows full dashboard. |
| **Complexity** | **M** — UX and layout work. |

---

### 2.7 Themes & Appearance

| Field | Details |
|-------|---------|
| **Description** | Light/dark/auto themes; optional accent colors. |
| **PulseBar Gap** | Uses system appearance. |
| **Suggested Approach** | Add `AppSettingsV2.theme` (light/dark/system). Apply via `.preferredColorScheme` or environment. Low risk. |
| **Complexity** | **S** — Standard SwiftUI. |

---

### 2.8 Extended Alerts (Memory, Disk, Network)

| Field | Details |
|-------|---------|
| **Description** | Alert on network throughput spikes, disk space critical, etc. |
| **PulseBar Gap** | Covered in Tier 1.5; this extends to network. |
| **Suggested Approach** | Add `networkInBytesPerSec`, `networkOutBytesPerSec`, `diskThroughputBytesPerSec` to `AlertRule`. Same pattern as Tier 1.5. |
| **Complexity** | **S** — Incremental. |

---

## Tier 3 — Stretch / Long-term

*Features that require significant effort, external dependencies, or safety gates.*

### 3.1 Fan Control

| Field | Details |
|-------|---------|
| **Description** | Manual fan speed control (e.g., set RPM or curve). |
| **PulseBar Gap** | Read-only fan telemetry via AppleSMC. Architecture explicitly states "No fan write/control path." |
| **Suggested Approach** | **Safety gate first:** Roadmap requires (1) public/system-supported control interface confirmation, (2) bounded control + readback validation, (3) watchdog/failsafe rollback-to-auto, (4) conflict handling with other tools, (5) safety matrix. If gate passes: SMC write keys (e.g., `F0Md` for manual mode) — **requires root, carries hardware risk.** Prefer deferring; focus on thermal alerts and cooling guidance. |
| **Complexity** | **L** — Safety, testing, and liability. |

---

### 3.2 Weather

| Field | Details |
|-------|---------|
| **Description** | Current weather in menu bar or popover. |
| **PulseBar Gap** | Not in scope. |
| **Suggested Approach** | Use `WeatherKit` (Apple) or Open-Meteo/OpenWeatherMap API. Requires API key, network, location. Add optional Weather tab; respect privacy (location permission). |
| **Complexity** | **M** — API integration; scope creep for a system monitor. |

---

### 3.3 World Clocks

| Field | Details |
|-------|---------|
| **Description** | Multiple timezone clocks in menu or popover. |
| **PulseBar Gap** | Not in scope. |
| **Suggested Approach** | `DateFormatter` with `timeZone`; user-configurable list of timezones. Simple implementation. |
| **Complexity** | **S** — Straightforward; lower priority for core monitoring. |

---

### 3.4 Calendar Integration

| Field | Details |
|-------|---------|
| **Description** | Show upcoming calendar events. |
| **PulseBar Gap** | Not in scope. |
| **Suggested Approach** | `EventKit` framework. Requires Calendar permission. |
| **Complexity** | **M** — Permission and UX; diverges from system monitoring. |

---

### 3.5 Network: Per-App Bandwidth

| Field | Details |
|-------|---------|
| **Description** | Bandwidth usage per application. |
| **PulseBar Gap** | Aggregated only. |
| **Suggested Approach** | `nettop` provides per-app stats but has high CPU cost (~95% reported). `netusage`/`symptomsd` are alternatives. No clean public API; Apple DTS has stated no high-level API exists. NKE-based approach is complex and requires special entitlements. |
| **Complexity** | **L** — API limitations; CPU cost; possible Process-based nettop parsing with throttling. |

---

### 3.6 Bluetooth Device List

| Field | Details |
|-------|---------|
| **Description** | List connected Bluetooth devices. |
| **PulseBar Gap** | Not in scope. |
| **Suggested Approach** | `IOBluetooth` (deprecated) or `CoreBluetooth` (limited). `system_profiler SPBluetoothDataType` or `bluetoothctl` (if available). |
| **Complexity** | **M** — Deprecated/limited APIs. |

---

### 3.7 Disk: Per-App I/O

| Field | Details |
|-------|---------|
| **Description** | Disk I/O per process. |
| **PulseBar Gap** | System-wide only. |
| **Suggested Approach** | `fs_usage` or `iotop`-style tools; `libproc` + `proc_pidinfo` for file I/O. Privileged and heavy. |
| **Complexity** | **L** — Similar to per-app network. |

---

### 3.8 Import/Export Profiles

| Field | Details |
|-------|---------|
| **Description** | Export and import profile settings. |
| **PulseBar Gap** | Roadmap lists as long-term. |
| **Suggested Approach** | Serialize `AppSettingsV2` / `ProfileSettings` to JSON; file picker for import. Validate schema version. |
| **Complexity** | **S** — Straightforward. |

---

## Delivery Status Snapshot (as of 2026-02-22)

| Item | Tier | Status | Target Phase |
|------|------|--------|--------------|
| Battery & power metrics | 1.1 | Done | Phase 1 |
| Memory compressed + swap | 1.2 phase 1 | Done | Phase 1 |
| Alerts: memory + disk | 1.5 | Done | Phase 1 |
| CPU load average | 1.6 | Done | Phase 1 |
| Disk S.M.A.R.T. status | 1.4 | Done | Phase 2 |
| Disk read/write split | 1.3 | Done | Phase 2 |
| Network per-interface | 1.7 | Done | Phase 2 |
| Memory per-app breakdown | 1.2 phase 2 | Planned | Phase 3 (optional) |
| Tier 2 package | 2.x | Planned | Post Tier 1 |
| Tier 3 package | 3.x | Deferred | Long-term |

## Phased Execution Plan (Tier 1 First)

### Phase 1 (10 working days)

1. Battery provider + UI surface
2. Memory compressed/swap
3. Memory/disk alert extensions
4. CPU load average
5. Tests and docs sync

### Phase 2 (9-10 working days)

1. Disk S.M.A.R.T. status
2. Disk read/write split (after source lock)
3. Network per-interface breakdown
4. Validation/perf pass + docs sync

### Phase 3 (5-7 working days, optional)

1. Per-app memory breakdown behind toggle
2. Sampling throttling + overhead guardrails
3. UI polish for dense process-level memory data

## Summary Matrix

| Tier | Items | Suggested Order | Status |
|------|-------|-----------------|--------|
| **Tier 1** | Battery, Memory (compressed/swap), Disk read/write, S.M.A.R.T., Alerts (mem/disk), Load average, Network per-interface | Battery → Memory → Alerts → Load avg → S.M.A.R.T. → Disk R/W → Network | Implemented |
| **Tier 2** | CPU/GPU freq, GPU util, Power sensors, Wi-Fi/VPN, Sparklines, Compact menu, Themes, Extended alerts | Sparklines → Themes → Wi-Fi/VPN → Freq → Power → Compact menu | Planned |
| **Tier 3** | Fan control, Weather, Clocks, Calendar, Per-app network, Bluetooth, Per-app disk, Profile import/export | Profile import/export → Clocks → Weather; defer Fan, per-app | Deferred/long-term |

---

## Architecture Notes

- **New providers:** Follow `MetricProvider` protocol; add `MetricID`; register in `AppCoordinator`; add tab if needed.
- **Privileged features:** Extend `PrivilegedTelemetryIPC` contract and `PulseBarHelper`; keep app functional when helper unavailable.
- **Alerts:** Extend `AlertRule`/`AlertEngine`; add Settings UI.
- **Battery:** Uses IOKit; no privilege required.
- **Fan control:** Do not implement without explicit safety gate approval.
