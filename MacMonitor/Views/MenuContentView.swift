import SwiftUI

func colorForTemperature(_ temp: Double) -> Color {
    switch temp {
    case ..<60: return .green
    case 60..<80: return .yellow
    case 80..<95: return .orange
    default: return .red
    }
}

func colorForCPU(_ usage: Double) -> Color {
    switch usage {
    case ..<50: return .green
    case 50..<75: return .yellow
    case 75..<90: return .orange
    default: return .red
    }
}

func colorForMemory(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.6: return .green
    case 0.6..<0.8: return .yellow
    case 0.8..<0.9: return .orange
    default: return .red
    }
}

struct MenuContentView: View {
    @Bindable var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 280, height: 560)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: Thermal
            HStack {
                Text("Thermal Pressure:")
                Text(monitor.pressure.displayName)
                    .foregroundColor(monitor.pressure.color)
                    .fontWeight(.semibold)
                Spacer()
                if let temp = monitor.temperature {
                    Text(TemperatureUnit.format(temp, fahrenheit: monitor.useFahrenheit))
                        .foregroundColor(colorForTemperature(temp))
                        .fontWeight(.semibold)
                        .help("Source: \(monitor.temperatureSource ?? "Unknown")")
                }
            }
            .font(.headline)

            if monitor.history.count >= 2 {
                HistoryGraphView(history: monitor.history, showFanSpeed: monitor.showFanSpeed)
            }

            // MARK: Intel throttle (real speed limit)
            if monitor.hasIntelThrottle, let throttle = monitor.throttle {
                Divider()
                HStack {
                    Text("CPU Speed Limit:")
                    Spacer()
                    Text("\(throttle.speedLimit ?? 100)%")
                        .foregroundColor(throttle.isThrottled ? .orange : .green)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                if let scheduler = throttle.schedulerLimit {
                    labelValue("Scheduler Limit", "\(scheduler)%")
                }
                if let cpus = throttle.availableCPUs {
                    labelValue("Available CPUs", "\(cpus)")
                }
            }

            // MARK: CPU
            Divider()
            if let cpu = monitor.cpuUsage {
                UsageBar(
                    label: "CPU",
                    fraction: cpu.total / 100,
                    valueText: "\(Int(cpu.total.rounded()))%",
                    color: colorForCPU(cpu.total)
                )
                .help("User \(Int(cpu.user.rounded()))% · System \(Int(cpu.system.rounded()))%")
            }
            if monitor.showCPUGraph, monitor.history.count >= 2 {
                MetricLineGraph(
                    history: monitor.history,
                    value: { $0.cpuUsage.map { $0 / 100 } },
                    lineColor: .blue
                )
            }

            // MARK: Memory
            Divider()
            if let mem = monitor.memory {
                UsageBar(
                    label: "Memory",
                    fraction: mem.usedFraction,
                    valueText: "\(ByteFormat.gb(mem.used)) / \(ByteFormat.gb(mem.total))",
                    color: colorForMemory(mem.usedFraction),
                    badge: mem.pressure.isElevated ? (mem.pressure.displayName, mem.pressure.color) : nil
                )
                .help("Wired \(ByteFormat.gb(mem.wired)) · Compressed \(ByteFormat.gb(mem.compressed))")

                if mem.swapUsed > 0 {
                    Text("Swap used: \(ByteFormat.gb(mem.swapUsed))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            if monitor.showMemoryGraph, monitor.history.count >= 2 {
                MetricLineGraph(
                    history: monitor.history,
                    value: { $0.memoryUsedFraction },
                    lineColor: .purple,
                    band: { $0.memoryPressure?.color }
                )
            }

            // MARK: Statistics
            if !monitor.timeInEachState.isEmpty {
                Divider()
                Text("Thermal Statistics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimeBreakdownView(
                    timeInEachState: monitor.timeInEachState,
                    totalDuration: monitor.totalHistoryDuration
                )
            }

            // MARK: Windows
            Divider()
            HStack {
                Button("All Sensors…") {
                    openWindow(id: "sensors")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Graphs…") {
                    openWindow(id: "graphs")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .controlSize(.small)

            // MARK: Settings
            Divider()
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLoginManager.shared.isEnabled },
                set: { _ in LaunchAtLoginManager.shared.toggle() }
            ))
            .controlSize(.small)

            Group {
                if monitor.hasFans {
                    Toggle("Show Fan Speed", isOn: $monitor.showFanSpeed)
                }
                Toggle("Show CPU Graph", isOn: $monitor.showCPUGraph)
                Toggle("Show Memory Graph", isOn: $monitor.showMemoryGraph)
                Toggle("Average Temperature (vs Hottest)", isOn: $monitor.averageTemperature)
                Toggle("Fahrenheit", isOn: $monitor.useFahrenheit)
                Toggle("Show Temperature in Menu Bar", isOn: $monitor.showTemperatureInMenuBar)
                Toggle("Show CPU in Menu Bar", isOn: $monitor.showCPUInMenuBar)
            }
            .controlSize(.small)

            Stepper("Refresh: \(monitor.refreshInterval)s", value: $monitor.refreshInterval, in: 1...10)
                .controlSize(.small)

            // MARK: Notifications
            Divider()
            Text("Notifications")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                Toggle("On Heavy", isOn: $monitor.notifyOnHeavy)
                Toggle("On Critical", isOn: $monitor.notifyOnCritical)
                Toggle("On Recovery", isOn: $monitor.notifyOnRecovery)
                Toggle("Sound", isOn: $monitor.notificationSound)
            }
            .controlSize(.small)

            Divider()
            HStack {
                Button("About") { openAboutWindow() }
                    .controlSize(.small)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func openAboutWindow() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }
}
