import SwiftUI

/// The menu-bar label: a "vitals" glyph tinted by thermal pressure, followed by whichever
/// metrics the user has ticked to display — laid out side by side, or stacked when compact.
struct MenuBarIcon: View {
    var monitor: SystemMonitor

    private struct Readout: Identifiable {
        let id = UUID()
        let systemImage: String
        let text: String
    }

    private var readouts: [Readout] {
        var items: [Readout] = []

        if monitor.showTemperatureInMenuBar, let temp = monitor.temperature {
            items.append(.init(
                systemImage: "thermometer.medium",
                text: TemperatureUnit.format(temp, fahrenheit: monitor.useFahrenheit)
            ))
        }
        if monitor.showCPUInMenuBar, let cpu = monitor.cpuUsage {
            items.append(.init(systemImage: "cpu", text: "\(Int(cpu.total.rounded()))%"))
        }
        if monitor.showMemoryInMenuBar, let mem = monitor.memory {
            items.append(.init(
                systemImage: "memorychip",
                text: "\(Int((mem.usedFraction * 100).rounded()))%"
            ))
        }
        if monitor.showStorageUsedInMenuBar, let storage = monitor.storage {
            items.append(.init(systemImage: "internaldrive.fill", text: ByteFormat.compact(storage.used)))
        }
        if monitor.showStorageAvailableInMenuBar, let storage = monitor.storage {
            items.append(.init(systemImage: "internaldrive", text: ByteFormat.compact(storage.available)))
        }
        return items
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(iconColor)

            if !readouts.isEmpty {
                if monitor.compactMenuBar {
                    VStack(alignment: .leading, spacing: -1) {
                        ForEach(readouts) { readoutView($0) }
                    }
                    .font(.system(size: 8.5, weight: .medium))
                } else {
                    HStack(spacing: 6) {
                        ForEach(readouts) { readoutView($0) }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func readoutView(_ readout: Readout) -> some View {
        HStack(spacing: 2) {
            Image(systemName: readout.systemImage)
                .imageScale(.small)
            Text(readout.text)
                .monospacedDigit()
        }
    }

    private var iconColor: Color {
        switch monitor.pressure {
        case .nominal, .unknown: return .primary
        default: return monitor.pressure.color
        }
    }
}
