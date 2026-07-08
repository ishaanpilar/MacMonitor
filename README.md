# MacMonitor

A lightweight macOS menu-bar app that monitors your Mac's **thermal pressure, CPU usage, and memory** — with live graphs and throttling alerts. No admin privileges, no helper daemon.

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
