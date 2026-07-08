# Changelog

All notable changes to MacMonitor are documented here.

## [1.1.0] - 2026-07-09

### Added
- **Fan control**: force fans to a target speed (30–100%) instead of relying on macOS's automatic
  curve. Works on Intel and Apple Silicon (best-effort on Apple Silicon, since the SMC firmware
  doesn't officially expose manual control there). Always fails safe back to Auto — on toggling
  off, on app quit, and automatically if any sensor reaches a critical temperature (100°C).

### Changed
- Softened the thermal-state and history-graph fill colors and rounded card corners for a less
  saturated, more legible look at a glance.
- Redesigned `MetricCard`/`MetricProgressBar` styling shared across the Thermal, CPU, Memory, and
  Storage cards.

## [1.0.0] - Initial release

- Thermal, CPU, and memory monitoring in the menu bar.
- Storage monitoring and per-value menu-bar toggles.
- Launch-at-login, notifications, and update checking.
