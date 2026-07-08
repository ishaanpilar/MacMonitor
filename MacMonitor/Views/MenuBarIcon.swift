import SwiftUI

struct MenuBarIcon: View {
    let pressure: ThermalPressure
    let temperature: Double?
    let showTemperature: Bool
    var fahrenheit: Bool = false
    var cpuUsage: Double?
    var showCPU: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(pressure.color, .primary)
            if showTemperature, let temp = temperature {
                Text(TemperatureUnit.format(temp, fahrenheit: fahrenheit))
                    .monospacedDigit()
            }
            if showCPU, let cpu = cpuUsage {
                Text("\(Int(cpu.rounded()))%")
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        switch pressure {
        case .nominal: return "thermometer.low"
        case .moderate: return "thermometer.medium"
        case .heavy: return "thermometer.high"
        case .critical: return "thermometer.sun.fill"
        case .unknown: return "thermometer.variable.and.figure"
        }
    }
}
