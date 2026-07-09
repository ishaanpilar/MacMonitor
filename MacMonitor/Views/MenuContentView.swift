import SwiftUI

func colorForTemperature(_ temp: Double) -> Color {
    switch temp {
    case ..<60: return Palette.thermal
    case 60..<80: return .yellow
    case 80..<95: return .orange
    default: return .red
    }
}

/// Metric value colour: the accent normally, warming to orange/red as usage gets high.
func metricValueColor(_ accent: Color, _ fraction: Double) -> Color {
    if fraction >= 0.9 { return .red }
    if fraction >= 0.75 { return .orange }
    return accent
}

struct MenuContentView: View {
    @Bindable var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 288, height: 580)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            thermalCard
            if monitor.hasIntelThrottle, let throttle = monitor.throttle {
                throttleCard(throttle)
            }
            fanControlCard
            cpuCard
            memoryCard
            storageCard
            statisticsCard
            windowsRow
            settingsCard
            notificationsCard
            footer
        }
        .padding(12)
    }

    // MARK: - Thermal

    private var thermalCard: some View {
        MetricCard(
            icon: "thermometer.medium",
            title: "Thermal",
            accent: Palette.thermal,
            valueText: monitor.temperature.map { TemperatureUnit.format($0, fahrenheit: monitor.useFahrenheit) } ?? "—",
            valueColor: monitor.temperature.map(colorForTemperature),
            badge: (monitor.pressure.displayName, monitor.pressure.color),
            menuBar: $monitor.showTemperatureInMenuBar
        ) {
            if monitor.history.count >= 2 {
                HistoryGraphView(history: monitor.history, showFanSpeed: monitor.showFanSpeed)
            }
        }
        .help(monitor.temperatureSource.map { "Source: \($0)" } ?? "")
    }

    // MARK: - Intel throttle

    private func throttleCard(_ throttle: ThrottleInfo) -> some View {
        MetricCard(
            icon: "speedometer",
            title: "CPU Speed Limit",
            accent: throttle.isThrottled ? .orange : Palette.thermal,
            valueText: "\(throttle.speedLimit ?? 100)%",
            valueColor: throttle.isThrottled ? .orange : Palette.thermal
        ) {
            VStack(alignment: .leading, spacing: 3) {
                if let scheduler = throttle.schedulerLimit {
                    labelValue("Scheduler Limit", "\(scheduler)%")
                }
                if let cpus = throttle.availableCPUs {
                    labelValue("Available CPUs", "\(cpus)")
                }
            }
        }
    }

    // MARK: - Fan Control

    @ViewBuilder private var fanControlCard: some View {
        if monitor.hasFanControl {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "fan.fill")
                        .foregroundStyle(Palette.thermal)
                    Text("Fan Control")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Custom", isOn: $monitor.fanControlEnabled)
                        .toggleStyle(.switch)
                }

                if monitor.fanControlEnabled {
                    HStack {
                        Slider(
                            value: $monitor.fanTargetPercentage,
                            in: FanController.minPercentage...FanController.maxPercentage,
                            step: 5
                        )
                        Text("\(Int(monitor.fanTargetPercentage))%")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .disabled(!FanController.shared.isAuthorized)

                    if FanController.shared.isRequestingAuthorization {
                        Label("Waiting for administrator approval…", systemImage: "lock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if let error = FanController.shared.authorizationError {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Button("Grant Permission") {
                                FanController.shared.retryAuthorization()
                            }
                            .controlSize(.mini)
                        }
                    } else if !FanController.shared.isAuthorized {
                        // swiftlint:disable:next line_length
                        Text("Requires one-time administrator approval to install a fan-control helper.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        // swiftlint:disable:next line_length
                        Text("Forces fans to at least this speed. Jumps to 100% automatically if temperatures get critical, and reverts to Auto on quit.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .controlSize(.small)
            .cardStyle()
        }
    }

    // MARK: - CPU

    @ViewBuilder private var cpuCard: some View {
        if let cpu = monitor.cpuUsage {
            MetricCard(
                icon: "cpu",
                title: "CPU",
                accent: Palette.cpu,
                valueText: "\(Int(cpu.total.rounded()))%",
                valueColor: metricValueColor(Palette.cpu, cpu.total / 100),
                menuBar: $monitor.showCPUInMenuBar
            ) {
                MetricProgressBar(fraction: cpu.total / 100, accent: Palette.cpu)
                if monitor.showCPUGraph, monitor.history.count >= 2 {
                    MetricLineGraph(
                        history: monitor.history,
                        value: { $0.cpuUsage.map { $0 / 100 } },
                        lineColor: Palette.cpu
                    )
                }
            }
            .help("User \(Int(cpu.user.rounded()))% · System \(Int(cpu.system.rounded()))%")
        }
    }

    // MARK: - Memory

    @ViewBuilder private var memoryCard: some View {
        if let mem = monitor.memory {
            MetricCard(
                icon: "memorychip",
                title: "Memory",
                accent: Palette.memory,
                valueText: "\(ByteFormat.gb(mem.used)) / \(ByteFormat.gb(mem.total))",
                valueColor: metricValueColor(Palette.memory, mem.usedFraction),
                badge: mem.pressure.isElevated ? (mem.pressure.displayName, mem.pressure.color) : nil,
                menuBar: $monitor.showMemoryInMenuBar
            ) {
                MetricProgressBar(fraction: mem.usedFraction, accent: Palette.memory)
                if mem.swapUsed > 0 {
                    Text("Swap: \(ByteFormat.gb(mem.swapUsed))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if monitor.showMemoryGraph, monitor.history.count >= 2 {
                    MetricLineGraph(
                        history: monitor.history,
                        value: { $0.memoryUsedFraction },
                        lineColor: Palette.memory,
                        band: { $0.memoryPressure?.color }
                    )
                }
            }
            .help("Wired \(ByteFormat.gb(mem.wired)) · Compressed \(ByteFormat.gb(mem.compressed))")
        }
    }

    // MARK: - Storage

    @ViewBuilder private var storageCard: some View {
        if let storage = monitor.storage {
            MetricCard(
                icon: "internaldrive",
                title: "Storage",
                accent: Palette.storage,
                valueText: "\(ByteFormat.gb(storage.used)) / \(ByteFormat.gb(storage.total))",
                valueColor: metricValueColor(Palette.storage, storage.usedFraction),
                menuBar: $monitor.showStorageUsedInMenuBar
            ) {
                MetricProgressBar(fraction: storage.usedFraction, accent: Palette.storage)
                HStack {
                    Text("Available")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteFormat.gb(storage.available))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    MenuBarToggle(isOn: $monitor.showStorageAvailableInMenuBar)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Statistics

    @ViewBuilder private var statisticsCard: some View {
        if !monitor.timeInEachState.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Thermal Statistics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimeBreakdownView(
                    timeInEachState: monitor.timeInEachState,
                    totalDuration: monitor.totalHistoryDuration
                )
            }
            .cardStyle()
        }
    }

    // MARK: - Windows

    private var windowsRow: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "sensors")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("All Sensors", systemImage: "sensor")
                    .frame(maxWidth: .infinity)
            }
            Button {
                openWindow(id: "graphs")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Graphs", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLoginManager.shared.isEnabled },
                set: { _ in LaunchAtLoginManager.shared.toggle() }
            ))

            if monitor.hasFans {
                Toggle("Show Fan Speed", isOn: $monitor.showFanSpeed)
            }
            Toggle("Show CPU Graph", isOn: $monitor.showCPUGraph)
            Toggle("Show Memory Graph", isOn: $monitor.showMemoryGraph)
            Toggle("Average Temperature (vs Hottest)", isOn: $monitor.averageTemperature)
            Toggle("Fahrenheit", isOn: $monitor.useFahrenheit)
            Toggle("Compact Menu Bar (stacked)", isOn: $monitor.compactMenuBar)

            Stepper("Refresh: \(monitor.refreshInterval)s", value: $monitor.refreshInterval, in: 1...10)

            Text("Tip: tap the ◎ next to any value to show it in the menu bar.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .controlSize(.small)
        .cardStyle()
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notifications")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("On Heavy", isOn: $monitor.notifyOnHeavy)
            Toggle("On Critical", isOn: $monitor.notifyOnCritical)
            Toggle("On Recovery", isOn: $monitor.notifyOnRecovery)
            Toggle("Sound", isOn: $monitor.notificationSound)
        }
        .controlSize(.small)
        .cardStyle()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("About") { openAboutWindow() }
                .controlSize(.small)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .controlSize(.small)
        }
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func openAboutWindow() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }
}
