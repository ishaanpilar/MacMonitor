import SwiftUI

@main
struct MacMonitorApp: App {
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            MenuBarIcon(
                pressure: monitor.pressure,
                temperature: monitor.temperature,
                showTemperature: monitor.showTemperatureInMenuBar,
                fahrenheit: monitor.useFahrenheit,
                cpuUsage: monitor.cpuUsage?.total,
                showCPU: monitor.showCPUInMenuBar
            )
        }
        .menuBarExtraStyle(.window)

        Window("About MacMonitor", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Sensors", id: "sensors") {
            SensorsView(monitor: monitor)
        }
        .windowResizability(.contentSize)

        Window("Graphs", id: "graphs") {
            GraphsWindowView(monitor: monitor)
        }
        .windowResizability(.contentMinSize)
    }
}
