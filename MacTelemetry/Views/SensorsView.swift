import SwiftUI

/// A browsable list of every discovered sensor with its live value. Tapping a sensor toggles
/// whether it feeds the headline temperature (none selected = automatic CPU-sensor behaviour).
struct SensorsView: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensors")
                .font(.headline)

            Text("Tap sensors to include them in the headline temperature. None selected = automatic (CPU sensors).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if monitor.sortedSensors.isEmpty {
                Spacer()
                Text("No sensors discovered.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.sortedSensors, id: \.name) { sensor in
                            sensorRow(sensor)
                            Divider()
                        }
                    }
                }
            }

            HStack {
                Text("\(monitor.sortedSensors.count) sensors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !monitor.selectedSensors.isEmpty {
                    Button("Reset to automatic") { monitor.selectedSensors = [] }
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 320, height: 440)
    }

    private func sensorRow(_ sensor: (name: String, value: Double)) -> some View {
        let selected = monitor.isSensorSelected(sensor.name)
        return HStack {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(sensor.name)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(TemperatureUnit.format(sensor.value, fahrenheit: monitor.useFahrenheit))
                .foregroundStyle(colorForTemperature(sensor.value))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { monitor.toggleSensor(sensor.name) }
    }
}

/// The graphs, popped out into their own resizable window. Reuses the popover graph views.
struct GraphsWindowView: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if monitor.history.count >= 2 {
                labelled("Thermal / Temperature") {
                    HistoryGraphView(history: monitor.history, showFanSpeed: monitor.showFanSpeed)
                }
                labelled("CPU Usage") {
                    MetricLineGraph(
                        history: monitor.history,
                        value: { $0.cpuUsage.map { $0 / 100 } },
                        lineColor: .blue
                    )
                }
                labelled("Memory Usage") {
                    MetricLineGraph(
                        history: monitor.history,
                        value: { $0.memoryUsedFraction },
                        lineColor: .purple,
                        band: { $0.memoryPressure?.color }
                    )
                }
                if monitor.hasIntelThrottle {
                    labelled("CPU Speed Limit") {
                        MetricLineGraph(
                            history: monitor.history,
                            value: { $0.cpuSpeedLimit.map { $0 / 100 } },
                            lineColor: .orange
                        )
                    }
                }
            } else {
                Text("Collecting data…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 360)
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
