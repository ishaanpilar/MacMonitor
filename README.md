# MacMonitor

<img src="docs/icon.png" alt="MacMonitor" width="120" align="right">

A lightweight macOS menu-bar app that monitors your Mac's **thermal pressure, CPU usage, memory, and storage** — with live graphs and throttling alerts. No admin privileges, no helper daemon.

<p align="center">
  <img src="docs/screenshots/menu.png" width="300" alt="Menu bar popover">
  &nbsp;
  <img src="docs/screenshots/menu-graphs.png" width="300" alt="Popover with CPU and memory graphs">
</p>
<p align="center">
  <img src="docs/screenshots/graphs.png" width="620" alt="Detachable graphs window">
</p>

## Features

- **Thermal pressure** in the menu bar (nominal / moderate / heavy / critical), read from the system's true 5-level signal
- **CPU temperature** read from the SMC, with automatic discovery of every hardware sensor
- **CPU usage** and **memory usage + pressure** indicators with live 10-minute graphs
- **Fan speed** on Macs with fans
- **Sensor browser** — see every sensor, pick which drive the headline temperature
- Max-vs-average temperature, °C/°F, configurable refresh interval, detachable graphs window
- Real CPU speed-limit / scheduler-limit readout on Intel Macs
- Configurable throttling notifications
- Launch at Login

## Requirements

- macOS 15.0+ (Sequoia)
- Apple Silicon or Intel

## Install

The app is ad-hoc signed but **not notarized** yet, so macOS quarantines it. Clear the flag once
after installing (this is a one-time step).

### Homebrew

```bash
brew install --cask ishaanpilar/tap/macmonitor
xattr -dr com.apple.quarantine /Applications/MacMonitor.app
```

### Download

1. Download `MacMonitor-x.y.z.dmg` from [Releases](https://github.com/ishaanpilar/MacMonitor/releases), open it, and drag **MacMonitor** to Applications.
2. Clear the quarantine flag once, in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacMonitor.app
   ```
   **Or** without Terminal: double-click the app, dismiss the "could not verify" prompt, then open
   **System Settings → Privacy & Security**, scroll to *Security*, and click **Open Anyway**.
3. Launch it — the vitals icon appears in your menu bar.

> On recent macOS, right-click → Open no longer bypasses this, and Homebrew removed the
> `--no-quarantine` flag — the `xattr` command (or *Open Anyway*) is the reliable way until the app is notarized.

## Build

Open `MacMonitor.xcodeproj` in Xcode and press ⌘R, or:

```bash
xcodebuild -project MacMonitor.xcodeproj -scheme MacMonitor -configuration Release build
```

## How it works

- **Thermal pressure** — the Darwin notification `com.apple.system.thermalpressurelevel` (the same 5-level source `powermetrics` uses), read without root.
- **Temperature / fan** — read directly from the SMC over IOKit; all `T*` sensor keys are enumerated and cached, with an IOHIDEventSystem fallback.
- **CPU usage** — `host_statistics(HOST_CPU_LOAD_INFO)`, sampled as tick deltas.
- **Memory** — `host_statistics64(HOST_VM_INFO64)` (App + Wired + Compressed), swap via `vm.swapusage`, pressure via `kern.memorystatus_vm_pressure_level`.
- **Intel throttle** — `pmset -g therm` (Intel only; skipped on Apple Silicon).

SMC sensor-key tables are derived from the [Stats](https://github.com/exelban/stats) project.

## License

MIT © 2025 Ishaan Pilar
